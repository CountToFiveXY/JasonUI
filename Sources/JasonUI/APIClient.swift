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

struct RecognizedLine: Decodable, Equatable, Identifiable {
    let text: String
    let confidence: Double

    /// Lines can repeat, so position is the stable identity.
    var id: String { "\(text)#\(confidence)" }
}

struct RecognizedText: Decodable, Equatable {
    let text: String
    let lines: [RecognizedLine]
}

struct CarSummary: Decodable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct CarListResponse: Decodable, Equatable {
    let cars: [CarSummary]
}

struct MapSummary: Decodable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    /// Optional, so a backend predating the field still decodes.
    let chineseName: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case chineseName = "chinese_name"
    }

    var displayName: String { leaderboardDisplayName(name, chineseName) }
}

/// `Name (中文名)`, or just the name while no translation is recorded.
func leaderboardDisplayName(_ name: String, _ chineseName: String?) -> String {
    guard let chineseName, !chineseName.isEmpty else { return name }
    return "\(name) (\(chineseName))"
}

struct MapListResponse: Decodable, Equatable {
    let maps: [MapSummary]
}

struct LapTimeEntry: Decodable, Equatable, Identifiable {
    let rank: Int
    let car: String
    let seconds: Double

    var id: String { car }

    /// The recorded time as the leaderboard shows it, for example `19.357`.
    ///
    /// Three decimals: lap times are recorded to a thousandth of a second, and
    /// rounding further would make distinct records look identical. The unit
    /// lives in the column heading rather than on every row.
    var displayTime: String { String(format: "%.3f", seconds) }
}

struct TrackLeaderboard: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let chineseName: String?
    let times: [LapTimeEntry]

    enum CodingKeys: String, CodingKey {
        case id, name, times
        case chineseName = "chinese_name"
    }

    var displayName: String { leaderboardDisplayName(name, chineseName) }
}

/// A track leaderboard that knows which map it came from, for a line-up whose
/// tracks span several maps.
struct MapTrackLeaderboard: Decodable, Equatable {
    let id: String
    let name: String
    let chineseName: String?
    let times: [LapTimeEntry]
    let mapID: String
    let mapName: String
    let mapChineseName: String?
    /// The name that was looked up, which recognition may have spelled differently.
    let requestedName: String

    enum CodingKeys: String, CodingKey {
        case id, name, times
        case chineseName = "chinese_name"
        case mapID = "map_id"
        case mapName = "map_name"
        case mapChineseName = "map_chinese_name"
        case requestedName = "requested_name"
    }

    /// Unique per slot: the same track id could be asked for twice.
    var slotKey: String { "\(mapID)/\(id)" }
    var displayName: String { leaderboardDisplayName(name, chineseName) }
    var mapDisplayName: String { leaderboardDisplayName(mapName, mapChineseName) }

    func replacingTimes(_ times: [LapTimeEntry]) -> MapTrackLeaderboard {
        MapTrackLeaderboard(
            id: id,
            name: name,
            chineseName: chineseName,
            times: times,
            mapID: mapID,
            mapName: mapName,
            mapChineseName: mapChineseName,
            requestedName: requestedName
        )
    }
}

/// A track in the selector: its name, and the map it belongs to.
struct MapTrackSummary: Decodable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
    let chineseName: String?
    let mapID: String
    let mapName: String
    let mapChineseName: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case chineseName = "chinese_name"
        case mapID = "map_id"
        case mapName = "map_name"
        case mapChineseName = "map_chinese_name"
    }

    var slotKey: String { "\(mapID)/\(id)" }
    var displayName: String { leaderboardDisplayName(name, chineseName) }
    var mapDisplayName: String { leaderboardDisplayName(mapName, mapChineseName) }
    /// What a one-line menu row shows: the track, then its map.
    var menuLabel: String { "\(displayName) — \(mapName)" }
}

struct TrackListResponse: Decodable, Equatable {
    let tracks: [MapTrackSummary]
}

struct TrackLookup: Decodable, Equatable {
    let tracks: [MapTrackLeaderboard]
    let unmatched: [String]
}

struct MapLeaderboard: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let chineseName: String?
    let tracks: [TrackLeaderboard]

    enum CodingKeys: String, CodingKey {
        case id, name, tracks
        case chineseName = "chinese_name"
    }
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

    func maps() async throws -> [MapSummary] {
        let response: MapListResponse = try await request(
            path: "v1/leaderboard/maps",
            method: "GET"
        )
        return response.maps
    }

    /// Every car holding a time anywhere, for the car selector.
    func cars() async throws -> [CarSummary] {
        let response: CarListResponse = try await request(
            path: "v1/leaderboard/cars",
            method: "GET"
        )
        return response.cars
    }

    func createMap(name: String, tracks: [String]) async throws -> MapLeaderboard {
        struct Body: Encodable { let name: String; let tracks: [String] }
        return try await request(
            path: "v1/leaderboard/maps",
            method: "POST",
            body: Body(name: name, tracks: tracks)
        )
    }

    /// Every track with the map it belongs to, for a track selector.
    func tracks() async throws -> [MapTrackSummary] {
        let response: TrackListResponse = try await request(
            path: "v1/leaderboard/tracks",
            method: "GET"
        )
        return response.tracks
    }

    /// Leaderboards for a list of track names, whatever maps they belong to.
    func lookupTracks(names: [String]) async throws -> TrackLookup {
        struct Body: Encodable { let names: [String] }
        return try await request(
            path: "v1/leaderboard/tracks/lookup",
            method: "POST",
            body: Body(names: names)
        )
    }

    func mapLeaderboard(mapID: String) async throws -> MapLeaderboard {
        try await request(path: "v1/leaderboard/maps/\(mapID)", method: "GET")
    }

    func recordLapTime(
        mapID: String,
        trackID: String,
        car: String,
        seconds: Double
    ) async throws -> TrackLeaderboard {
        struct Body: Encodable { let car: String; let seconds: Double }
        return try await request(
            path: lapTimesPath(mapID: mapID, trackID: trackID),
            method: "PUT",
            body: Body(car: car, seconds: seconds)
        )
    }

    func deleteLapTime(
        mapID: String,
        trackID: String,
        car: String
    ) async throws -> TrackLeaderboard {
        try await request(
            path: lapTimesPath(mapID: mapID, trackID: trackID) + "/" + car,
            method: "DELETE"
        )
    }

    /// Read the words out of an image. The bytes are the request body, so
    /// nothing has to be base64-encoded or wrapped in a multipart form.
    func readText(image: Data, contentType: String = "image/png") async throws -> RecognizedText {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/text-recognition"))
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = image
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(RecognizedText.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
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

    /// The maps collection in the Firebase console.
    func firestoreMapsURL() -> URL? {
        firestoreDocumentURL(path: "maps")
    }

    func firestoreMapURL(mapID: String) -> URL? {
        firestoreDocumentURL(path: "maps/\(mapID)")
    }

    func firestoreOrderURL(orderID: String) -> URL? {
        firestoreDocumentURL(path: "orders/\(orderID)")
    }

    private func firestoreDocumentURL(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "console.firebase.google.com"
        let escapedPath = path.split(separator: "/").map { "~2F" + $0 }.joined()
        components.path = "/project/jasonapp-xm0830/firestore/databases/-default-/data/\(escapedPath)"
        return components.url
    }

    private func lapTimesPath(mapID: String, trackID: String) -> String {
        "v1/leaderboard/maps/\(mapID)/tracks/\(trackID)/times"
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
