import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppUpdateManager {
    enum State: Equatable {
        case idle
        case checking
        case current
        case updateAvailable
        case updating
    }

    private struct GitHubCommit: Decodable {
        let sha: String
    }

    private struct CommandFailure: LocalizedError, Sendable {
        let command: String
        let status: Int32
        let output: String

        var errorDescription: String? {
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "\(command) failed with exit code \(status)."
                : "\(command) failed: \(String(detail.suffix(1_500)))"
        }
    }

    var state: State = .idle
    var progress = 0.0
    var progressLabel = ""
    var errorMessage: String?

    private static let commitURL = URL(
        string: "https://api.github.com/repos/CountToFiveXY/JasonUI/commits/main"
    )!
    private static let cloneURL = "https://github.com/CountToFiveXY/JasonUI.git"
    private static let installedAppURL = URL(fileURLWithPath: "/Applications/JasonApp.app")
    private static let checkInterval = Duration.seconds(15 * 60)

    var updateAvailable: Bool { state == .updateAvailable }
    var isChecking: Bool { state == .checking }
    var isUpdating: Bool { state == .updating }
    var releaseLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return Self.releaseLabel(for: version)
    }

    nonisolated static func releaseLabel(for version: String?) -> String {
        guard let version = version?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else { return "v—" }
        return version.hasPrefix("v") ? version : "v\(version)"
    }

    func monitorForUpdates() async {
        await checkForUpdates()
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.checkInterval)
            } catch {
                return
            }
            await checkForUpdates()
        }
    }

    func checkForUpdates() async {
        guard !isChecking, !isUpdating else { return }
        state = .checking
        errorMessage = nil

        do {
            let remoteCommit = try await fetchRemoteCommit()
            let installedCommit = try await installedSourceCommit()
            state = remoteCommit == installedCommit ? .current : .updateAvailable
        } catch {
            state = .idle
            errorMessage = error.localizedDescription
        }
    }

    func installUpdate() async {
        guard updateAvailable else {
            await checkForUpdates()
            return
        }

        state = .updating
        errorMessage = nil
        progress = 0.03
        progressLabel = "Preparing…"

        let fileManager = FileManager.default
        let updateRoot = fileManager.temporaryDirectory
            .appendingPathComponent("JasonApp-Update-\(UUID().uuidString)", isDirectory: true)
        let checkoutURL = updateRoot.appendingPathComponent("JasonUI", isDirectory: true)
        let packagedAppURL = checkoutURL
            .appendingPathComponent(".build/app-package/JasonApp.app", isDirectory: true)
        let stagedAppURL = URL(fileURLWithPath: "/Applications/.JasonApp-update-\(UUID().uuidString).app")
        var oldAppBackupURL: URL?

        do {
            try fileManager.createDirectory(at: updateRoot, withIntermediateDirectories: true)

            progress = 0.10
            progressLabel = "Downloading…"
            _ = try await Self.runCommand(
                executable: "/usr/bin/git",
                arguments: ["clone", "--depth", "1", "--branch", "main", Self.cloneURL, checkoutURL.path]
            )

            progress = 0.30
            progressLabel = "Testing…"
            _ = try await Self.runCommand(
                executable: "/usr/bin/xcrun",
                arguments: ["swift", "test"],
                currentDirectory: checkoutURL
            )

            progress = 0.52
            progressLabel = "Building…"
            _ = try await Self.runCommand(
                executable: checkoutURL.appendingPathComponent("scripts/package_app.sh").path,
                currentDirectory: checkoutURL
            )

            progress = 0.76
            progressLabel = "Verifying…"
            _ = try await Self.runCommand(
                executable: "/usr/bin/codesign",
                arguments: ["--verify", "--deep", "--strict", packagedAppURL.path]
            )

            progress = 0.84
            progressLabel = "Installing…"
            _ = try await Self.runCommand(
                executable: "/usr/bin/ditto",
                arguments: [packagedAppURL.path, stagedAppURL.path]
            )
            _ = try await Self.runCommand(
                executable: "/usr/bin/codesign",
                arguments: ["--verify", "--deep", "--strict", stagedAppURL.path]
            )

            if fileManager.fileExists(atPath: Self.installedAppURL.path) {
                let backupURL = updateRoot.appendingPathComponent("JasonApp.previous.app")
                try fileManager.moveItem(at: Self.installedAppURL, to: backupURL)
                oldAppBackupURL = backupURL
            }

            do {
                try fileManager.moveItem(at: stagedAppURL, to: Self.installedAppURL)
            } catch {
                if let oldAppBackupURL {
                    try? fileManager.moveItem(at: oldAppBackupURL, to: Self.installedAppURL)
                }
                throw error
            }

            progress = 1.0
            progressLabel = "Relaunching…"
            _ = try await Self.runCommand(
                executable: "/usr/bin/open",
                arguments: ["-n", Self.installedAppURL.path]
            )
            NSApplication.shared.terminate(nil)
        } catch {
            if fileManager.fileExists(atPath: stagedAppURL.path) {
                try? fileManager.removeItem(at: stagedAppURL)
            }
            if let oldAppBackupURL,
               !fileManager.fileExists(atPath: Self.installedAppURL.path) {
                try? fileManager.moveItem(at: oldAppBackupURL, to: Self.installedAppURL)
            }
            try? fileManager.removeItem(at: updateRoot)
            state = .updateAvailable
            progress = 0
            progressLabel = ""
            errorMessage = error.localizedDescription
        }
    }

    private func fetchRemoteCommit() async throws -> String {
        var request = URLRequest(url: Self.commitURL)
        request.setValue("JasonApp/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(GitHubCommit.self, from: data).sha
    }

    private func installedSourceCommit() async throws -> String {
        if let commit = Bundle.main.object(forInfoDictionaryKey: "JasonSourceCommit") as? String,
           !commit.isEmpty,
           commit != "development" {
            return commit
        }

        let sourceURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("JasonApp/JasonUI", isDirectory: true)
        let output = try await Self.runCommand(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "HEAD"],
            currentDirectory: sourceURL
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func runCommand(
        executable: String,
        arguments: [String] = [],
        currentDirectory: URL? = nil
    ) async throws -> String {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let outputPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectory
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = [
                "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"
            ].joined(separator: ":")
            process.environment = environment

            try process.run()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: data, as: UTF8.self)
            guard process.terminationStatus == 0 else {
                throw CommandFailure(
                    command: ([executable] + arguments).joined(separator: " "),
                    status: process.terminationStatus,
                    output: output
                )
            }
            return output
        }.value
    }
}
