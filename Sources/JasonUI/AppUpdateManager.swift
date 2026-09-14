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

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }

        /// The packaged app CI attached to this release, if it published one.
        var appArchive: Asset? {
            assets.first { $0.name == AppUpdateManager.releaseAssetName }
        }
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

    private struct UpdatePreparationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    var state: State = .idle
    @ObservationIgnored private var remoteCommit: String?
    @ObservationIgnored private var installedCommit: String?
    var progress = 0.0
    var progressLabel = ""
    var errorMessage: String?

    private static let commitURL = URL(
        string: "https://api.github.com/repos/CountToFiveXY/JasonUI/commits/main"
    )!
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/CountToFiveXY/JasonUI/releases/latest"
    )!
    nonisolated static let releaseAssetName = "JasonApp.zip"
    private static let installedAppURL = URL(fileURLWithPath: "/Applications/JasonApp.app")
    private static let checkInterval = Duration.seconds(15 * 60)
    private static let frontendDirectoryKey = "frontendDirectory"

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
            self.remoteCommit = remoteCommit
            self.installedCommit = installedCommit
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
        let stagedAppURL = URL(fileURLWithPath: "/Applications/.JasonApp-update-\(UUID().uuidString).app")
        var oldAppBackupURL: URL?

        do {
            try fileManager.createDirectory(at: updateRoot, withIntermediateDirectories: true)
            let packagedAppURL = try await preparePackagedApp(in: updateRoot)

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
            try scheduleSingleInstanceRelaunch()
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

    /// The app bundle to install: the build CI published, or one compiled here.
    ///
    /// Downloading is the normal path and needs nothing but the network, so a
    /// Mac without Xcode or a checkout can still update. Compiling is kept as
    /// a fallback for a machine that has the source but cannot reach a build —
    /// no published release yet, or working offline.
    private func preparePackagedApp(in updateRoot: URL) async throws -> URL {
        progress = 0.10
        progressLabel = "Downloading…"
        do {
            return try await downloadPackagedApp(into: updateRoot)
        } catch let downloadError {
            guard let checkoutURL = try? await resolveFrontendDirectory(allowSelection: false) else {
                throw downloadError
            }
            return try await buildPackagedApp(from: checkoutURL)
        }
    }

    private func downloadPackagedApp(into updateRoot: URL) async throws -> URL {
        let release = try await fetchLatestRelease()
        guard let asset = release.appArchive else {
            throw UpdatePreparationError(
                message: "Release \(release.tagName) has no \(Self.releaseAssetName) attached yet."
            )
        }

        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("JasonApp/1.0", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let archiveURL = updateRoot.appendingPathComponent(Self.releaseAssetName)
        try FileManager.default.moveItem(at: temporaryURL, to: archiveURL)

        progress = 0.45
        progressLabel = "Unpacking…"
        let unpackedURL = updateRoot.appendingPathComponent("unpacked", isDirectory: true)
        _ = try await Self.runCommand(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, unpackedURL.path]
        )

        let appURL = unpackedURL.appendingPathComponent("JasonApp.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw UpdatePreparationError(message: "The downloaded archive contained no JasonApp.app.")
        }
        // Nothing here sets the quarantine flag, but strip it in case the
        // archive was produced somewhere that did.
        _ = try? await Self.runCommand(
            executable: "/usr/bin/xattr",
            arguments: ["-dr", "com.apple.quarantine", appURL.path]
        )

        // CI may not have finished building the newest commit yet, in which
        // case the published build is the one already installed.
        if let built = Self.sourceCommit(of: appURL), built == installedCommit {
            throw UpdatePreparationError(
                message: "The newest published build is the one already installed. "
                    + "CI may still be building the latest commit — try again shortly."
            )
        }
        return appURL
    }

    private func buildPackagedApp(from checkoutURL: URL) async throws -> URL {
        let changes = try await Self.runCommand(
            executable: "/usr/bin/git",
            arguments: ["status", "--porcelain"],
            currentDirectory: checkoutURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard changes.isEmpty else {
            throw UpdatePreparationError(
                message: "JasonUI has local changes. Commit or discard them before updating."
            )
        }

        progress = 0.20
        progressLabel = "Updating source…"
        _ = try await Self.runCommand(
            executable: "/usr/bin/git",
            arguments: ["pull", "--ff-only", "origin", "main"],
            currentDirectory: checkoutURL
        )

        progress = 0.34
        progressLabel = "Testing…"
        _ = try await Self.runCommand(
            executable: "/usr/bin/xcrun",
            arguments: ["swift", "test"],
            currentDirectory: checkoutURL
        )

        progress = 0.56
        progressLabel = "Building…"
        _ = try await Self.runCommand(
            executable: checkoutURL.appendingPathComponent("scripts/package_app.sh").path,
            currentDirectory: checkoutURL
        )
        return checkoutURL.appendingPathComponent(".build/app-package/JasonApp.app", isDirectory: true)
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("JasonApp/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw UpdatePreparationError(
                message: "No published build is available to download yet."
            )
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    /// The commit an app bundle was built from, as stamped by package_app.sh.
    nonisolated static func sourceCommit(of appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil
              ) as? [String: Any] else { return nil }
        return plist["JasonSourceCommit"] as? String
    }

    private func scheduleSingleInstanceRelaunch() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-c",
            """
            current_pid="$1"
            app_path="$2"
            while kill -0 "$current_pid" 2>/dev/null; do sleep 0.1; done
            /usr/bin/pkill -TERM -x JasonUI 2>/dev/null || true
            for _ in {1..30}; do
                /usr/bin/pgrep -x JasonUI >/dev/null 2>&1 || break
                sleep 0.1
            done
            exec /usr/bin/open "$app_path"
            """,
            "JasonAppRelaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            Self.installedAppURL.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
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

        let sourceURL = try await resolveFrontendDirectory(allowSelection: false)
        let output = try await Self.runCommand(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "HEAD"],
            currentDirectory: sourceURL
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveFrontendDirectory(allowSelection: Bool) async throws -> URL {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let savedPath = UserDefaults.standard.string(forKey: Self.frontendDirectoryKey) {
            candidates.append(URL(fileURLWithPath: savedPath, isDirectory: true))
        }
        if let backendPath = UserDefaults.standard.string(forKey: "backendDirectory") {
            candidates.append(
                URL(fileURLWithPath: backendPath, isDirectory: true)
                    .deletingLastPathComponent()
                    .appendingPathComponent("JasonUI", isDirectory: true)
            )
        }
        candidates.append(
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Workspace/JasonUI", isDirectory: true)
        )

        if let directory = Self.validFrontendDirectory(in: candidates) {
            UserDefaults.standard.set(directory.path, forKey: Self.frontendDirectoryKey)
            return directory
        }

        if allowSelection {
            let panel = NSOpenPanel()
            panel.title = "Choose the JasonUI repository"
            panel.message = "Select the local JasonUI folder to update and rebuild JasonApp."
            panel.prompt = "Choose JasonUI"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            if panel.runModal() == .OK,
               let selected = panel.url,
               let directory = Self.validFrontendDirectory(in: [selected]) {
                UserDefaults.standard.set(directory.path, forKey: Self.frontendDirectoryKey)
                return directory
            }
        }

        throw UpdatePreparationError(
            message: "Could not find the local JasonUI repository. Run Install JasonApp.command again."
        )
    }

    nonisolated static func validFrontendDirectory(in candidates: [URL]) -> URL? {
        let fileManager = FileManager.default
        for candidate in candidates {
            let directory = candidate.standardizedFileURL.resolvingSymlinksInPath()
            let package = directory.appendingPathComponent("Package.swift")
            let gitDirectory = directory.appendingPathComponent(".git", isDirectory: true)
            if fileManager.fileExists(atPath: package.path),
               fileManager.fileExists(atPath: gitDirectory.path) {
                return directory
            }
        }
        return nil
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
