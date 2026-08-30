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
    var isClosing = false
    var health: HealthResponse?
    var backendState = ServiceState.unknown
    var redisState = ServiceState.unknown
    var temporalState = ServiceState.unknown
    var errorMessage: String?

    private static let serverKey = "serverAddress"
    @ObservationIgnored private var servicesProcess: Process?
    @ObservationIgnored private var servicesLogHandle: FileHandle?

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
        if let client, (try? await client.health()) != nil {
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

            var environment = ProcessInfo.processInfo.environment
            let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            environment["PATH"] = ["/opt/homebrew/bin", "/usr/local/bin", inheritedPath]
                .joined(separator: ":")
            process.environment = environment

            do {
                let logHandle = try makeServicesLogHandle()
                process.standardOutput = logHandle
                process.standardError = logHandle
                try process.run()
                servicesProcess = process
                servicesLogHandle = logHandle
            } catch {
                errorMessage = "Could not start services: \(error.localizedDescription)"
                return
            }
        }

        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(500))
            if let client, (try? await client.health()) != nil {
                await checkConnection()
                return
            }
            if servicesProcess?.isRunning == false { break }
        }

        await checkConnection()
        let logPath = servicesLogURL().path
        errorMessage = "Services did not become ready. Review the startup log at \(logPath)"
    }

    func closeServer() async {
        isClosing = true
        errorMessage = nil
        defer { isClosing = false }

        if servicesProcess?.isRunning == true {
            servicesProcess?.terminate()
        } else {
            let startupScript = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Workspace/JasonPython/scripts/run_local.sh")
            let stopProcess = Process()
            stopProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            stopProcess.arguments = ["-TERM", "-f", startupScript.path]
            do {
                try stopProcess.run()
                stopProcess.waitUntilExit()
            } catch {
                errorMessage = "Could not close the server: \(error.localizedDescription)"
                return
            }
        }

        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(250))
            guard let client else { break }
            if (try? await client.health()) == nil { break }
        }

        servicesLogHandle?.closeFile()
        servicesLogHandle = nil
        servicesProcess = nil
        health = nil
        backendState = .unavailable("Stopped")
        redisState = .unknown
        temporalState = .unavailable("Stopped")
    }

    private func servicesLogURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/JasonApp", isDirectory: true)
            .appendingPathComponent("services.log")
    }

    private func makeServicesLogHandle() throws -> FileHandle {
        let logURL = servicesLogURL()
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        if let marker = "\n--- JasonApp activation \(Date()) ---\n".data(using: .utf8) {
            try handle.write(contentsOf: marker)
        }
        return handle
    }
}
