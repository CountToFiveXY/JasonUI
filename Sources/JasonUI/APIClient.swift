import Foundation

struct HealthResponse: Decodable, Equatable {
    let status: String
    let redis: String
}

struct WorkflowResponse: Decodable, Equatable {
    let workflowID: String
    let result: String

    enum CodingKeys: String, CodingKey {
        case workflowID = "workflow_id"
        case result
    }
}

struct ShortenResponse: Decodable, Equatable {
    let shortKey: String
}

enum CardType: String, CaseIterable, Identifiable, Codable {
    case se = "SE"
    case sp = "SP"
    case ch = "CH"

    var id: String { rawValue }
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

    func shorten(url: String) async throws -> ShortenResponse {
        try await request(path: "v1/shorten", method: "POST", body: ["url": url])
    }

    func hello() async throws -> WorkflowResponse {
        try await request(path: "workflows/hello", method: "POST")
    }

    func greeting(name: String) async throws -> WorkflowResponse {
        try await request(path: "workflows/greeting", method: "POST", body: ["name": name])
    }

    func displayImage() async throws -> Data {
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

    func shortURL(for key: String) -> URL? {
        baseURL.appendingPathComponent(key)
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

