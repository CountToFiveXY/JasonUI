import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    enum ServiceState: Equatable {
        case unknown
        case checking
        case running(String? = nil)
        case unavailable(String? = nil)
        case unsupported
    }

    var serverAddress: String {
        didSet { UserDefaults.standard.set(serverAddress, forKey: Self.serverKey) }
    }
    var isChecking = false
    var isActivating = false
    var health: HealthResponse?
    var backendState = ServiceState.unknown
    var redisState = ServiceState.unknown
    var temporalState = ServiceState.unknown
    var errorMessage: String?

    private static let serverKey = "serverAddress"
    @ObservationIgnored private var servicesProcess: Process?

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
            backendState = .unavailable("Invalid server URL")
            redisState = .unknown
            temporalState = .unsupported
            return
        }
        isChecking = true
        backendState = .checking
        redisState = .checking
        temporalState = .checking
        defer { isChecking = false }

        async let healthCheck = client.health()
        async let temporalCheck = client.temporalIsAvailable()

        do {
            health = try await healthCheck
            backendState = .running()
            redisState = health?.redis.lowercased() == "connected"
                ? .running("Connected")
                : .unavailable(health?.redis)
            errorMessage = nil
        } catch {
            health = nil
            backendState = .unavailable(error.localizedDescription)
            redisState = .unknown
            errorMessage = error.localizedDescription
        }

        switch await temporalCheck {
        case true:
            temporalState = .running("Web UI reachable on port 8233")
        case false:
            temporalState = .unavailable("Web UI not reachable on port 8233")
        case nil:
            temporalState = .unsupported
        }
    }

    func activateAllServices() async {
        if backendState == .running() {
            await checkConnection()
            return
        }

        let backendDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Workspace/JasonPython", isDirectory: true)
        let startupScript = backendDirectory
            .appendingPathComponent("scripts/run_local.sh")

        guard FileManager.default.isExecutableFile(atPath: startupScript.path) else {
            errorMessage = "Startup script was not found at \(startupScript.path)"
            return
        }

        isActivating = true
        errorMessage = nil
        defer { isActivating = false }

        if servicesProcess?.isRunning != true {
            let process = Process()
            process.executableURL = startupScript
            process.currentDirectoryURL = backendDirectory
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                servicesProcess = process
            } catch {
                errorMessage = "Could not start services: \(error.localizedDescription)"
                return
            }
        }

        try? await Task.sleep(for: .seconds(3))
        await checkConnection()

        if backendState != .running(), servicesProcess?.isRunning == false {
            errorMessage = "The local service startup process stopped before the backend became ready."
        }
    }
}
