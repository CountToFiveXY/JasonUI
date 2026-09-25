import Foundation
import Testing
@testable import JasonUI

@Suite(.serialized)
struct APIClientTests {
    @Test func decodesHealthResponse() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path == "/health")
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"status":"OK","redis":"connected","kafka":"connected"}"#.utf8))
        }
        let response = try await client().health()
        #expect(response == HealthResponse(status: "OK", redis: "connected", kafka: "connected"))
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

    @Test func buildsFirestoreMapURL() {
        let url = client().firestoreMapURL(mapID: "new-york")
        #expect(
            url?.absoluteString ==
                "https://console.firebase.google.com/project/jasonapp-xm0830/firestore/databases/-default-/data/~2Fmaps~2Fnew-york"
        )
    }

    @Test func decodesMapListForTheSelector() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/leaderboard/maps")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"maps":[{"id":"san-francisco","name":"San Francisco","chinese_name":"旧金山"},{"id":"tokyo","name":"Tokyo"}]}"#.utf8)
            )
        }

        let maps = try await client().maps()

        // Release order comes from the API; the client must not re-sort.
        #expect(maps.map(\.id) == ["san-francisco", "tokyo"])
        #expect(maps.first?.displayName == "San Francisco (旧金山)")
        // A map with no translation yet shows just its name.
        #expect(maps.last?.displayName == "Tokyo")
    }

    @Test func loadsGalaxyLeaderboards() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/ranking/leaderboards")
            let data = Data(
                #"{"source":"https://al.galaxylens.de/leaderboards","leaderboards":[{"id":249,"name":"啤酒节","total_participants":192865,"status":"active","updated_at":"2026-09-25T04:00:05Z","tiers":[{"label":"1%","rank":1928,"time":"1:01.715"},{"label":"100%","rank":192865,"time":"1:53.604"}],"event":{"id":"event-1","name":"OKTOBER FAST TLE","end_date":"2026-09-30","type":"LIMITED_TIME_EVENT","subtype":null},"season":{"id":"season-1","name":"SUNSET SPEEDWAY","end_date":"2026-10-14","type":null,"subtype":null}}]}"#.utf8
            )
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let response = try await client().galaxyLeaderboards()

        #expect(response.leaderboards.count == 1)
        #expect(response.leaderboards[0].name == "啤酒节")
        #expect(response.leaderboards[0].tiers[0].rank == 1928)
        #expect(response.leaderboards[0].tiers[0].time == "1:01.715")
        #expect(response.leaderboards[0].totalParticipants == 192865)
        #expect(response.leaderboards[0].event?.name == "OKTOBER FAST TLE")
        #expect(response.leaderboards[0].event?.type == "LIMITED_TIME_EVENT")
        #expect(response.leaderboards[0].isTierOne == false)
        #expect(response.leaderboards[0].season?.name == "SUNSET SPEEDWAY")
    }

    @Test func sendsMapWithItsTwoTracks() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/leaderboard/maps")
            let body = try #require(requestBodyData(request))
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["name"] as? String == "New York")
            #expect(json["tracks"] as? [String] == ["A park In A run", "Harbor Sprint"])
            let data = Data(
                #"{"id":"new-york","name":"New York","tracks":[{"id":"a-park-in-a-run","name":"A park In A run","times":[]},{"id":"harbor-sprint","name":"Harbor Sprint","times":[]}]}"#.utf8
            )
            return (
                HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let created = try await client().createMap(
            name: "New York",
            tracks: ["A park In A run", "Harbor Sprint"]
        )

        #expect(created.id == "new-york")
        #expect(created.tracks.count == 2)
        let tracksWithoutTimes = created.tracks.filter(\.times.isEmpty).count
        #expect(tracksWithoutTimes == 2)
    }

    @Test func decodesRankedLapTimesForAMap() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/leaderboard/maps/new-york")
            let data = Data(
                #"{"id":"new-york","name":"New York","tracks":[{"id":"a-park-in-a-run","name":"A park In A run","times":[{"rank":1,"car":"C2","seconds":19.62},{"rank":2,"car":"C3","seconds":20.1}]},{"id":"harbor-sprint","name":"Harbor Sprint","times":[]}]}"#.utf8
            )
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let leaderboard = try await client().mapLeaderboard(mapID: "new-york")

        let fastest = try #require(leaderboard.tracks.first?.times.first)
        #expect(fastest.rank == 1)
        #expect(fastest.car == "C2")
        #expect(fastest.displayTime == "19.620")
        let slower = try #require(leaderboard.tracks.first?.times.last)
        #expect(slower.displayTime == "20.100")
        #expect(leaderboard.tracks.last?.times.isEmpty == true)
    }

    @Test func recordsALapTimeOnATrack() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.path == "/v1/leaderboard/maps/new-york/tracks/a-park-in-a-run/times")
            let body = try #require(requestBodyData(request))
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["car"] as? String == "C2")
            #expect(json["seconds"] as? Double == 19.62)
            let data = Data(
                #"{"id":"a-park-in-a-run","name":"A park In A run","times":[{"rank":1,"car":"C2","seconds":19.62}]}"#.utf8
            )
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let track = try await client().recordLapTime(
            mapID: "new-york",
            trackID: "a-park-in-a-run",
            car: "C2",
            seconds: 19.62
        )

        let cars = track.times.map(\.car)
        #expect(cars == ["C2"])
    }

    @Test func deletesACarFromATrack() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/v1/leaderboard/maps/new-york/tracks/a-park-in-a-run/times/C 2")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"id":"a-park-in-a-run","name":"A park In A run","times":[]}"#.utf8)
            )
        }

        let track = try await client().deleteLapTime(
            mapID: "new-york",
            trackID: "a-park-in-a-run",
            car: "C 2"
        )

        #expect(track.times.isEmpty)
    }

    @Test func decodesCarRosterForTheSelector() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/leaderboard/cars")
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"cars":[{"id":"c2","name":"c2"},{"id":"杰弟","name":"杰弟"}]}"#.utf8)
            )
        }

        let cars = try await client().cars()

        #expect(cars == [CarSummary(id: "c2", name: "c2"), CarSummary(id: "杰弟", name: "杰弟")])
    }

    @Test func postsAnImageAsTheBodyAndDecodesLines() async throws {
        let pixels = Data([0x89, 0x50, 0x4E, 0x47])
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/text-recognition")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/png")
            #expect(requestBodyData(request) == pixels)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"text":"WATERSLIDE WHIRL\nNOTRE DAME","lines":[{"text":"WATERSLIDE WHIRL","confidence":0.98},{"text":"NOTRE DAME","confidence":0.95}]}"#.utf8)
            )
        }

        let recognized = try await client().readText(image: pixels)

        let texts = recognized.lines.map(\.text)
        #expect(texts == ["WATERSLIDE WHIRL", "NOTRE DAME"])
        #expect(recognized.lines.first?.confidence == 0.98)
    }

    @Test func surfacesTextRecognitionErrors() async throws {
        MockURLProtocol.handler = { request in
            return (
                HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!,
                Data(#"{"detail":"Cloud Vision API has not been used in project"}"#.utf8)
            )
        }

        await #expect(throws: APIError.server(
            statusCode: 503,
            message: "Cloud Vision API has not been used in project"
        )) {
            try await client().readText(image: Data([0x1]))
        }
    }

    @Test func decodesTheTrackRosterForTheSelectors() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/leaderboard/tracks")
            let data = Data(#"""
            {"tracks":[
              {"id":"railroad-bustle","name":"Railroad Bustle","chinese_name":"喧闹铁路",
               "map_id":"san-francisco","map_name":"San Francisco","map_chinese_name":"旧金山"},
              {"id":"the-tunnel","name":"The Tunnel","map_id":"san-francisco","map_name":"San Francisco"}
            ]}
            """#.utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let tracks = try await client().tracks()

        #expect(tracks.count == 2)
        #expect(tracks[0].menuLabel == "Railroad Bustle (喧闹铁路) — San Francisco")
        #expect(tracks[0].slotKey == "san-francisco/railroad-bustle")
        // A track with no translation shows just its name.
        #expect(tracks[1].menuLabel == "The Tunnel — San Francisco")
    }

    @Test func looksUpTracksByNameAcrossMaps() async throws {
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/leaderboard/tracks/lookup")
            let body = try #require(requestBodyData(request))
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["names"] as? [String] == ["WATERSLIDE WHIRL", "NOT A TRACK"])
            let data = Data(#"""
            {"tracks":[{"id":"waterslide-whirl","name":"Waterslide Whirl","chinese_name":"滑水道旋流",
              "map_id":"singapore","map_name":"Singapore","map_chinese_name":"新加坡",
              "requested_name":"WATERSLIDE WHIRL",
              "times":[{"rank":1,"car":"狼","seconds":21.057}]}],
             "unmatched":["NOT A TRACK"]}
            """#.utf8)
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                data
            )
        }

        let lookup = try await client().lookupTracks(names: ["WATERSLIDE WHIRL", "NOT A TRACK"])

        let track = try #require(lookup.tracks.first)
        #expect(track.displayName == "Waterslide Whirl (滑水道旋流)")
        #expect(track.mapDisplayName == "Singapore (新加坡)")
        #expect(track.slotKey == "singapore/waterslide-whirl")
        #expect(track.requestedName == "WATERSLIDE WHIRL")
        #expect(lookup.unmatched == ["NOT A TRACK"])
    }

    @Test func replacingTimesKeepsTheTracksIdentity() {
        let track = MapTrackLeaderboard(
            id: "la-boca",
            name: "La Boca",
            chineseName: "拉博卡区",
            times: [],
            mapID: "buenos-aires",
            mapName: "Buenos Aires",
            mapChineseName: "布宜诺斯艾利斯",
            requestedName: "LA BOCA"
        )

        let updated = track.replacingTimes([
            LapTimeEntry(rank: 1, car: "狼", seconds: 24.001)
        ])

        #expect(updated.slotKey == track.slotKey)
        #expect(updated.displayName == track.displayName)
        #expect(updated.times.map(\.car) == ["狼"])
    }

    @Test func parsesTypedLapTimes() {
        #expect(LeaderboardTime.seconds(from: " 19.62 ") == 19.62)
        #expect(LeaderboardTime.seconds(from: "19,62") == 19.62)
        #expect(LeaderboardTime.seconds(from: "19.62s") == 19.62)
        #expect(LeaderboardTime.seconds(from: "") == nil)
        #expect(LeaderboardTime.seconds(from: "fast") == nil)
        #expect(LeaderboardTime.seconds(from: "0") == nil)
        #expect(LeaderboardTime.seconds(from: "-3") == nil)
    }

    @Test func requiresAndSanitizesCompactLeaderboardTimes() {
        #expect(LeaderboardTime.fixedSeconds(from: "19.620") == 19.620)
        #expect(LeaderboardTime.fixedSeconds(from: "9.620") == nil)
        #expect(LeaderboardTime.fixedSeconds(from: "19.62") == nil)
        #expect(LeaderboardTime.fixedSeconds(from: "119.620") == nil)
        #expect(LeaderboardTime.fixedSeconds(from: "19,620") == nil)
        #expect(LeaderboardTime.sanitizedFixedInput("19a.6209s") == "19.620")
        #expect(LeaderboardTime.sanitizedFixedInput("123456") == "12")
        #expect(LeaderboardTime.sanitizedFixedInput("19..62") == "19.62")
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
