import AppKit
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
    private static let backendDirectoryKey = "backendDirectory"
    @ObservationIgnored private var servicesProcess: Process?
    @ObservationIgnored private var servicesLogHandle: FileHandle?
    @ObservationIgnored private var activeBackendDirectory: URL?

    init() {
        let savedAddress = UserDefaults.standard.string(forKey: Self.serverKey)
        if savedAddress == nil || savedAddress == "http://127.0.0.1:8080" {
            serverAddress = "http://127.0.0.1:8000"
            UserDefaults.standard.set(serverAddress, forKey: Self.serverKey)
        } else {
            serverAddress = savedAddress!
        }
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

        guard let backendDirectory = await resolveBackendDirectory(allowSelection: true) else {
            return
        }
        let startupScript = backendDirectory.appendingPathComponent("scripts/run_local.sh")

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

        for _ in 0..<1_200 {
            try? await Task.sleep(for: .milliseconds(500))
            adoptBackendPort(from: backendDirectory)
            if let client, (try? await client.health()) != nil {
                await checkConnection()
                return
            }
            if servicesProcess?.isRunning == false { break }
        }

        await checkConnection()
        let logPath = servicesLogURL().path
        let logExcerpt = latestServicesLogExcerpt()
        errorMessage = if logExcerpt.isEmpty {
            "Services did not become ready. Review the startup log at \(logPath)"
        } else {
            "Services did not become ready:\n\(logExcerpt)\n\nFull log: \(logPath)"
        }
    }

    func closeServer() async {
        isClosing = true
        errorMessage = nil
        defer { isClosing = false }

        if servicesProcess?.isRunning == true {
            servicesProcess?.terminate()
        } else {
            guard let backendDirectory = await resolveBackendDirectory(allowSelection: false) else {
                return
            }
            let startupScript = backendDirectory.appendingPathComponent("scripts/run_local.sh")
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

    private func resolveBackendDirectory(allowSelection: Bool) async -> URL? {
        if let activeBackendDirectory,
           Self.validBackendDirectory(in: [activeBackendDirectory]) != nil {
            return activeBackendDirectory
        }

        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let currentDirectory = URL(
            fileURLWithPath: fileManager.currentDirectoryPath,
            isDirectory: true
        )
        var candidates: [URL] = []

        if let savedPath = UserDefaults.standard.string(forKey: Self.backendDirectoryKey) {
            candidates.append(URL(fileURLWithPath: savedPath, isDirectory: true))
        }
        if let environmentPath = ProcessInfo.processInfo.environment["JASONPYTHON_PATH"] {
            candidates.append(URL(fileURLWithPath: environmentPath, isDirectory: true))
        }
        candidates += [
            homeDirectory.appendingPathComponent("JasonApp/JasonPython", isDirectory: true),
            homeDirectory.appendingPathComponent("Workspace/JasonPython", isDirectory: true),
            homeDirectory.appendingPathComponent("Developer/JasonPython", isDirectory: true),
            currentDirectory,
            currentDirectory.appendingPathComponent("JasonPython", isDirectory: true),
            currentDirectory.deletingLastPathComponent()
                .appendingPathComponent("JasonPython", isDirectory: true)
        ]

        if let detectedDirectory = Self.validBackendDirectory(in: candidates) {
            rememberBackendDirectory(detectedDirectory)
            return detectedDirectory
        }

        guard allowSelection else {
            errorMessage = "Could not find the JasonPython project folder."
            return nil
        }
        guard let selectedDirectory = await chooseBackendDirectory() else {
            errorMessage = "JasonPython project folder was not selected."
            return nil
        }
        guard let validDirectory = Self.validBackendDirectory(in: [selectedDirectory]) else {
            errorMessage = "The selected folder does not contain an executable scripts/run_local.sh file."
            return nil
        }

        rememberBackendDirectory(validDirectory)
        return validDirectory
    }

    nonisolated static func validBackendDirectory(in candidates: [URL]) -> URL? {
        let fileManager = FileManager.default
        var visitedPaths = Set<String>()

        for candidate in candidates {
            let directory = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard visitedPaths.insert(directory.path).inserted else { continue }
            let script = directory.appendingPathComponent("scripts/run_local.sh")
            if fileManager.isExecutableFile(atPath: script.path) {
                return directory
            }
        }
        return nil
    }

    private func rememberBackendDirectory(_ directory: URL) {
        activeBackendDirectory = directory
        UserDefaults.standard.set(directory.path, forKey: Self.backendDirectoryKey)
    }

    private func chooseBackendDirectory() async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.title = "Choose the JasonPython Project Folder"
            panel.message = "Select the folder containing scripts/run_local.sh."
            panel.prompt = "Choose"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    private func servicesLogURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/JasonApp", isDirectory: true)
            .appendingPathComponent("services.log")
    }

    private func adoptBackendPort(from backendDirectory: URL) {
        let portFile = backendDirectory.appendingPathComponent(".venv/jasonapp-api-port")
        guard let value = try? String(contentsOf: portFile, encoding: .utf8),
              let port = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65_535).contains(port) else { return }

        let localAddress = "http://127.0.0.1:\(port)"
        if serverAddress != localAddress {
            serverAddress = localAddress
        }
    }

    private func latestServicesLogExcerpt() -> String {
        guard let data = try? Data(contentsOf: servicesLogURL()),
              let contents = String(data: data, encoding: .utf8) else { return "" }
        let latestActivation = contents.components(separatedBy: "--- JasonApp activation").last ?? contents
        return latestActivation
            .split(separator: "\n")
            .suffix(8)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
