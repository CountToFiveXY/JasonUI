import Foundation

struct HealthResponse: Decodable, Equatable {
    let status: String
    let redis: String
    let kafka: String?
}

struct WorkflowResponse: Decodable, Equatable {
    let workflowID: String
    let result: String

    enum CodingKeys: String, CodingKey {
        case workflowID = "workflow_id"
        case result
    }
}

struct OrderResponse: Decodable, Equatable {
    let id: String
    let userID: String
    let created: String
    let workflowID: String

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case created
        case workflowID = "workflow_id"
    }
}

struct KafkaMessageResponse: Decodable, Equatable {
    let id: String
    let status: String
    let topic: String
    let partition: Int
    let offset: Int
}

struct ShortenResponse: Decodable, Equatable {
    let shortUrl: String
}

enum CardType: String, CaseIterable, Identifiable, Codable {
    case se = "SE"
    case sp = "SP"
    case ch = "CH"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ch: "Car Hunt"
        case .se: "Special Event"
        case .sp: "Spotlight"
        }
    }
}

enum APIError: LocalizedError, Equatable {
    case invalidBaseURL
    case invalidResponse
    case server(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Enter a valid HTTP or HTTPS server URL."
        case .invalidResponse:
            "The server returned an unreadable response."
        case let .server(statusCode, message):
            "Server error \(statusCode): \(message)"
        }
    }
}

struct APIClient: Sendable {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func health() async throws -> HealthResponse {
        try await request(path: "health", method: "GET")
    }

    func temporalIsAvailable() async -> Bool? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.host != nil else { return nil }
        components.scheme = "http"
        components.port = 8233
        components.path = "/"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (_, response) = try await session.data(for: request)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }

    func shorten(url: String) async throws -> ShortenResponse {
        try await request(path: "v1/shorten", method: "POST", body: ["url": url])
    }

    func hello() async throws -> WorkflowResponse {
        try await request(path: "workflows/hello", method: "POST")
    }

    func order(userID: String) async throws -> OrderResponse {
        try await request(path: "v1/order", method: "POST", body: ["user_id": userID])
    }

    func sendOrderSuccess(orderID: String) async throws -> KafkaMessageResponse {
        try await request(
            path: "v1/messages",
            method: "POST",
            body: ["id": orderID, "status": "SUCCESS"]
        )
    }

    func image() async throws -> Data {
        try await dataRequest(path: "display", method: "GET")
    }

    func ranking(total: Int, type: CardType, car: String) async throws -> Data {
        struct Body: Encodable { let total: Int; let type: CardType; let car: String }
        return try await dataRequest(
            path: "v1/ranking",
            method: "POST",
            body: Body(total: total, type: type, car: car)
        )
    }

    func shortURL(for path: String) -> URL? {
        if let absoluteURL = URL(string: path), absoluteURL.scheme != nil {
            return absoluteURL
        }
        return path.split(separator: "/").reduce(baseURL) { url, component in
            url.appendingPathComponent(String(component))
        }
    }

    func temporalWorkflowURL(workflowID: String, namespace: String = "default") -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              components.host != nil else { return nil }
        components.scheme = "http"
        components.port = 8233
        components.path = "/namespaces/\(namespace)/workflows"
        components.query = nil
        components.fragment = nil
        return components.url?.appendingPathComponent(workflowID)
    }

    func firestoreOrderURL(orderID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "console.firebase.google.com"
        components.path = "/project/jasonapp-xm0830/firestore/databases/-default-/data/~2Forders~2F\(orderID)"
        return components.url
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        let data = try await dataRequest(path: path, method: method, body: body)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    private func request<Response: Decodable>(path: String, method: String) async throws -> Response {
        let data = try await dataRequest(path: path, method: method)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    private func dataRequest<Body: Encodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func dataRequest(path: String, method: String) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            let detail = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).detail)
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw APIError.server(statusCode: response.statusCode, message: detail)
        }
        return data
    }
}

private struct ErrorEnvelope: Decodable {
    let detail: String
}
