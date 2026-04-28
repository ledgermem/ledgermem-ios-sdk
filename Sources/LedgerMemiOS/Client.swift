import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Async/await wrapper around the LedgerMem REST API.
///
/// Designed for application targets — the wrapper is thread-safe via an
/// actor and uses a single `URLSession` per instance.
public actor LedgerMemClient {
    public struct Configuration: Sendable {
        public var apiKey: String
        public var workspaceId: String
        public var baseURL: URL
        public var session: URLSession
        public var encoder: JSONEncoder
        public var decoder: JSONDecoder

        public init(
            apiKey: String,
            workspaceId: String,
            baseURL: URL = URL(string: "https://api.proofly.dev")!,
            session: URLSession = .shared,
            encoder: JSONEncoder = LedgerMemClient.defaultEncoder,
            decoder: JSONDecoder = LedgerMemClient.defaultDecoder
        ) {
            self.apiKey = apiKey
            self.workspaceId = workspaceId
            self.baseURL = baseURL
            self.session = session
            self.encoder = encoder
            self.decoder = decoder
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

    private func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }

    private func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Body?
    ) async throws -> Response {
        // Build URL via URLComponents so query strings survive intact and
        // the path is not double-encoded by appendingPathComponent.
        let basePath = config.baseURL.path
        let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        guard var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else {
            throw LedgerMemError.transport("invalid base URL")
        }
        components.path = trimmedBase + normalizedPath
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else {
            throw LedgerMemError.transport("failed to build URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(config.workspaceId, forHTTPHeaderField: "x-workspace-id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try config.encoder.encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await config.session.data(for: request)
        } catch {
            throw LedgerMemError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LedgerMemError.transport("Non-HTTP response")
        }

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
