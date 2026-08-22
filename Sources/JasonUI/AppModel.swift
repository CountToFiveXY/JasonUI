import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var serverAddress: String {
        didSet { UserDefaults.standard.set(serverAddress, forKey: Self.serverKey) }
    }
    var isChecking = false
    var health: HealthResponse?
    var errorMessage: String?

    private static let serverKey = "serverAddress"

    init() {
        serverAddress = UserDefaults.standard.string(forKey: Self.serverKey)
            ?? "http://127.0.0.1:8080"
    }

    var client: APIClient? {
        guard let url = URL(string: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased()),
              url.host != nil else { return nil }
        return APIClient(baseURL: url)
    }

    func checkConnection() async {
        guard let client else {
            errorMessage = APIError.invalidBaseURL.localizedDescription
            health = nil
            return
        }
        isChecking = true
        defer { isChecking = false }
        do {
            health = try await client.health()
            errorMessage = nil
        } catch {
            health = nil
            errorMessage = error.localizedDescription
        }
    }
}

