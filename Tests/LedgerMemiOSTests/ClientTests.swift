import XCTest
@testable import MnemoiOS

final class ClientTests: XCTestCase {
    override class func setUp() {
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override func setUp() {
        MockURLProtocol.reset()
    }

    private func makeClient() throws -> MnemoClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return try MnemoClient(config: .init(
            apiKey: "key",
            workspaceId: "ws_test",
            baseURL: URL(string: "https://api.getmnemo.xyz")!,
            session: session
        ))
    }

    func testSearchSendsHeadersAndDecodes() async throws {
        let client = try makeClient()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-workspace-id"), "ws_test")
            XCTAssertEqual(request.url?.path, "/v1/search")
            let body = """
            { "hits": [
              {
                "memory": {
                  "id": "m1",
                  "text": "hello",
                  "tags": ["x"],
                  "createdAt": "2026-01-01T00:00:00Z",
                  "updatedAt": "2026-01-01T00:00:00Z",
                  "workspaceId": "ws_test"
                },
                "score": 0.9
              }
            ] }
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8))
        }
        let hits = try await client.search(SearchRequest(query: "hello"))
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.memory.id, "m1")
    }

    func testCreateRoundTrip() async throws {
        let client = try makeClient()
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let body = """
            {
              "id": "m2",
              "text": "added",
              "tags": [],
              "createdAt": "2026-01-01T00:00:00Z",
              "updatedAt": "2026-01-01T00:00:00Z",
              "workspaceId": "ws_test"
            }
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8))
        }
        let memory = try await client.create(CreateMemoryInput(text: "added"))
        XCTAssertEqual(memory.id, "m2")
    }

    func testHTTPErrorBubbles() async throws {
        let client = try makeClient()
        MockURLProtocol.handler = { request in
            let body = #"{ "error": "missing_workspace", "code": "auth.invalid" }"#
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
                    Data(body.utf8))
        }
        do {
            _ = try await client.list()
            XCTFail("expected failure")
        } catch let MnemoError.http(status, message, code) {
            XCTAssertEqual(status, 401)
            XCTAssertEqual(message, "missing_workspace")
            XCTAssertEqual(code, "auth.invalid")
        }
    }
}

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() { handler = nil }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
