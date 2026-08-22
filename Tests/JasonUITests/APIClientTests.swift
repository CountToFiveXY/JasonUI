import Foundation
import Testing
@testable import JasonUI

@Suite(.serialized)
struct APIClientTests {
    @Test func decodesHealthResponse() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path == "/health")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"status":"OK","redis":"connected"}"#.utf8))
        }
        let response = try await client().health()
        #expect(response == HealthResponse(status: "OK", redis: "connected"))
    }

    @Test func sendsShortenRequest() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/shorten")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"shortUrl":"go/3FzaP09x"}"#.utf8))
        }
        let response = try await client().shorten(url: "https://example.com/path")
        #expect(response.shortUrl == "go/3FzaP09x")
        #expect(client().shortURL(for: response.shortUrl)?.absoluteString == "http://127.0.0.1:8080/go/3FzaP09x")
    }

    @Test func buildsTemporalWorkflowURL() {
        let url = client().temporalWorkflowURL(workflowID: "greeting-123")
        #expect(url?.absoluteString == "http://127.0.0.1:8233/namespaces/default/workflows/greeting-123")
    }

    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIClient(baseURL: URL(string: "http://127.0.0.1:8080")!, session: URLSession(configuration: configuration))
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
