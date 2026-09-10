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
        #expect(client().shortURL(for: response.shortUrl)?.absoluteString == "http://127.0.0.1:8000/go/3FzaP09x")
    }

    @Test func buildsTemporalWorkflowURL() {
        let url = client().temporalWorkflowURL(workflowID: "greeting-123")
        #expect(url?.absoluteString == "http://127.0.0.1:8233/namespaces/default/workflows/greeting-123")
    }

    @Test func buildsFirestoreOrderURL() {
        let url = client().firestoreOrderURL(orderID: "order-123")
        #expect(
            url?.absoluteString ==
                "https://console.firebase.google.com/project/jasonapp-xm0830/firestore/databases/-default-/data/~2Forders~2Forder-123"
        )
    }

    @Test func sendsOrderUserIDAndDecodesResponse() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/order")
            let body = try #require(requestBodyData(request))
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json == ["user_id": "user-123"])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = Data(
                #"{"id":"order-123","user_id":"user-123","created":"2026-09-07T12:00:00Z","workflow_id":"order-123"}"#.utf8
            )
            return (response, data)
        }

        let response = try await client().order(userID: "user-123")

        #expect(response.id == "order-123")
        #expect(response.userID == "user-123")
        #expect(response.workflowID == "order-123")
    }

    @Test func sendsKafkaOrderSuccessAndDecodesMetadata() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/messages")
            let body = try #require(requestBodyData(request))
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
            #expect(json == ["id": "order-123", "status": "SUCCESS"])
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 202,
                httpVersion: nil,
                headerFields: nil
            )!
            let data = Data(
                #"{"id":"order-123","status":"SUCCESS","topic":"backend-messages","partition":0,"offset":4}"#.utf8
            )
            return (response, data)
        }

        let response = try await client().sendOrderSuccess(orderID: "order-123")

        #expect(response.id == "order-123")
        #expect(response.status == "SUCCESS")
        #expect(response.topic == "backend-messages")
        #expect(response.partition == 0)
        #expect(response.offset == 4)
    }

    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return APIClient(baseURL: URL(string: "http://127.0.0.1:8000")!, session: URLSession(configuration: configuration))
    }
}

private func requestBodyData(_ request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else { return nil }
        if count == 0 { break }
        data.append(buffer, count: count)
    }
    return data
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
