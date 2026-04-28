import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Async/await wrapper around the LedgerMem REST API.
///
/// Designed for application targets — the wrapper is thread-safe via an
/// actor and uses a single `URLSession` per instance.
public actor LedgerMemClient {
    public static let defaultMaxRetries = 3
    private static let sdkVersion = "0.1.0"
    private static let retryBaseDelayNs: UInt64 = 200_000_000
    private static let retryMaxDelayNs: UInt64 = 5_000_000_000

    public struct Configuration: Sendable {
        public var apiKey: String
        public var workspaceId: String
        public var baseURL: URL
        public var session: URLSession
        public var encoder: JSONEncoder
        public var decoder: JSONDecoder
        public var maxRetries: Int

        public init(
            apiKey: String,
            workspaceId: String,
            baseURL: URL = URL(string: "https://api.proofly.dev")!,
            session: URLSession = .shared,
            encoder: JSONEncoder = LedgerMemClient.defaultEncoder,
            decoder: JSONDecoder = LedgerMemClient.defaultDecoder,
            maxRetries: Int = LedgerMemClient.defaultMaxRetries
        ) {
            self.apiKey = apiKey
            self.workspaceId = workspaceId
            self.baseURL = baseURL
            self.session = session
            self.encoder = encoder
            self.decoder = decoder
            self.maxRetries = max(0, maxRetries)
        }
    }

    public static var defaultEncoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    public static var defaultDecoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    public let config: Configuration

    public init(config: Configuration) throws {
        guard !config.apiKey.isEmpty else { throw LedgerMemError.invalidConfiguration("apiKey is empty") }
        guard !config.workspaceId.isEmpty else { throw LedgerMemError.invalidConfiguration("workspaceId is empty") }
        self.config = config
    }

    public func search(_ request: SearchRequest) async throws -> [SearchHit] {
        struct Wrapper: Decodable { let hits: [SearchHit] }
        let wrapper: Wrapper = try await send(method: "POST", path: "/v1/search", body: request)
        return wrapper.hits
    }

    public func list(cursor: String? = nil, limit: Int? = nil) async throws -> ListResult {
        var items: [URLQueryItem] = []
        if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        return try await send(method: "GET", path: "/v1/memories", query: items, body: Optional<Empty>.none)
    }

    public func get(id: String) async throws -> Memory {
        try await send(method: "GET", path: "/v1/memories/\(escape(id))", body: Optional<Empty>.none)
    }

    public func create(_ input: CreateMemoryInput) async throws -> Memory {
        try await send(method: "POST", path: "/v1/memories", body: input)
    }

    public func update(id: String, _ input: UpdateMemoryInput) async throws -> Memory {
        try await send(method: "PATCH", path: "/v1/memories/\(escape(id))", body: input)
    }

    public func delete(id: String) async throws {
        let _: Empty = try await send(method: "DELETE", path: "/v1/memories/\(escape(id))", body: Optional<Empty>.none)
    }

    // MARK: - Internals

    private struct Empty: Codable {}

    /// Percent-encode an identifier so it is safe to inject as a single path
    /// segment. `.urlPathAllowed` keeps "/" intact, which would let an id
    /// like "..%2F..%2Fadmin" smuggle in extra segments — restrict the
    /// allowed set to RFC 3986 unreserved characters instead.
    private func escape(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private static func isRetryable(status: Int) -> Bool {
        // 501 Not Implemented is permanent — retrying wastes round-trips.
        if status == 501 { return false }
        return status == 429 || (500..<600).contains(status)
    }

    private static func retryDelayNs(attempt: Int) -> UInt64 {
        let shift = min(attempt, 20)
        let capped = min(retryBaseDelayNs &* (UInt64(1) << shift), retryMaxDelayNs)
        return UInt64.random(in: 0...capped)
    }

    /// Parse the server's Retry-After header (delta-seconds form), capped
    /// at `retryMaxDelayNs` so a hostile server cannot stall the client.
    private static func retryAfterNs(from response: HTTPURLResponse) -> UInt64? {
        let raw = (response.value(forHTTPHeaderField: "Retry-After")
            ?? response.value(forHTTPHeaderField: "retry-after"))?
            .trimmingCharacters(in: .whitespaces)
        guard let raw, !raw.isEmpty, let secs = UInt64(raw) else { return nil }
        let ns = secs.multipliedReportingOverflow(by: 1_000_000_000)
        if ns.overflow { return retryMaxDelayNs }
        return min(ns.partialValue, retryMaxDelayNs)
    }

    private func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Body?
    ) async throws -> Response {
        // Build URL via URLComponents using `percentEncodedPath` so any
        // encoding we already applied to the id segment is preserved
        // verbatim. Assigning to `.path` decodes the input then re-encodes,
        // turning an id like `abc%2Fdef` into `abc%252Fdef`.
        guard var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else {
            throw LedgerMemError.transport("invalid base URL")
        }
        let basePath = components.percentEncodedPath
        let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        components.percentEncodedPath = trimmedBase + normalizedPath
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw LedgerMemError.transport("failed to build URL")
        }
        // Pre-encode the body once; we may resend it across retries.
        let encodedBody: Data?
        if let body {
            encodedBody = try config.encoder.encode(body)
        } else {
            encodedBody = nil
        }

        var attempt = 0
        var lastError: Error?
        let (data, http): (Data, HTTPURLResponse) = try await {
            while true {
                var request = URLRequest(url: url)
                request.httpMethod = method
                request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue(config.workspaceId, forHTTPHeaderField: "x-workspace-id")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("ledgermem-ios/\(Self.sdkVersion)", forHTTPHeaderField: "User-Agent")
                if let encodedBody {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = encodedBody
                }

                do {
                    let (rawData, rawResponse) = try await config.session.data(for: request)
                    guard let httpResp = rawResponse as? HTTPURLResponse else {
                        throw LedgerMemError.transport("Non-HTTP response")
                    }
                    if Self.isRetryable(status: httpResp.statusCode), attempt < config.maxRetries {
                        let hint = Self.retryAfterNs(from: httpResp)
                        let delay = hint ?? Self.retryDelayNs(attempt: attempt)
                        try await Task.sleep(nanoseconds: delay)
                        attempt += 1
                        continue
                    }
                    return (rawData, httpResp)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let urlError as URLError where urlError.code == .cancelled {
                    // URLSession reports caller cancellation as URLError(.cancelled);
                    // treat it like a Swift cancellation rather than a retryable
                    // failure, otherwise we would silently keep retrying after
                    // the consumer has already abandoned the call.
                    throw urlError
                } catch {
                    lastError = error
                    if attempt < config.maxRetries {
                        try await Task.sleep(nanoseconds: Self.retryDelayNs(attempt: attempt))
                        attempt += 1
                        continue
                    }
                    throw LedgerMemError.transport((lastError ?? error).localizedDescription)
                }
            }
        }()

        if !(200..<300).contains(http.statusCode) {
            throw decodeError(status: http.statusCode, data: data)
        }

        if Response.self == Empty.self || data.isEmpty {
            // Decoding Empty from {} or empty body
            if let empty = try? config.decoder.decode(Response.self, from: data.isEmpty ? Data("{}".utf8) : data) {
                return empty
            }
        }

        do {
            return try config.decoder.decode(Response.self, from: data)
        } catch {
            throw LedgerMemError.decoding(error.localizedDescription)
        }
    }

    private func decodeError(status: Int, data: Data) -> LedgerMemError {
        struct Body: Decodable { let error: String?; let code: String? }
        let body = (try? JSONDecoder().decode(Body.self, from: data))
        return .http(status: status, message: body?.error ?? "request failed", code: body?.code)
    }
}
