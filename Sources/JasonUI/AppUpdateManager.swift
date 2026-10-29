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
        case waitingForBuild
        case updateAvailable
        case updating
    }

    private struct GitHubCommit: Decodable {
        let sha: String
    }

    struct GitHubRelease: Decodable, Sendable {
        struct Asset: Decodable, Sendable {
            let name: String
            let browserDownloadURL: URL
            let state: String?
            let size: Int?

            enum CodingKeys: String, CodingKey {
                case name, state, size
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let assets: [Asset]
        let draft: Bool?
        let prerelease: Bool?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets, draft, prerelease
        }

        /// The packaged app CI attached to this release, if it published one.
        var appArchive: Asset? {
            guard draft != true, prerelease != true else { return nil }
            return assets.first {
                $0.name == AppUpdateManager.releaseAssetName
                    && $0.state == "uploaded" && ($0.size ?? 0) > 0
            }
        }
    }

    struct PublishedBuild: Sendable {
        let release: GitHubRelease
        let commit: String
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
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var publishedBuild: PublishedBuild?
    @ObservationIgnored private var installedCommit: String?
    @ObservationIgnored private var backendRemoteCommit: String?
    @ObservationIgnored private var backendDirectory: URL?
    @ObservationIgnored private var frontendNeedsUpdate = false
    @ObservationIgnored private var backendNeedsUpdate = false
    @ObservationIgnored private var completionPending = false
    var progress = 0.0
    var progressLabel = ""
    var errorMessage: String?

    private static let frontendCommitURL = URL(
        string: "https://api.github.com/repos/CountToFiveXY/JasonUI/commits/main"
    )!
    private static let backendCommitURL = URL(
        string: "https://api.github.com/repos/CountToFiveXY/JasonPython/commits/main"
    )!
    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/CountToFiveXY/JasonUI/releases/latest"
    )!
    nonisolated static let releaseAssetName = "JasonApp.zip"
    nonisolated private static let installedAppURL = URL(fileURLWithPath: "/Applications/JasonApp.app")
    private static let checkInterval = Duration.seconds(15 * 60)
    private static let frontendDirectoryKey = "frontendDirectory"
    private static let backendDirectoryKey = "backendDirectory"

    init(session: URLSession = .shared) {
        self.session = session
    }

    var isWaitingForBuild: Bool { state == .waitingForBuild }
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
                try await Task.sleep(for: isWaitingForBuild ? .seconds(60) : Self.checkInterval)
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
            let backendDirectory = try resolveBackendDirectory()
            async let remoteCommitTask = fetchRemoteCommit(from: Self.frontendCommitURL)
            async let publishedBuildTask = fetchPublishedBuild()
            async let installedCommitTask = installedSourceCommit()
            async let backendRemoteCommitTask = fetchRemoteCommit(from: Self.backendCommitURL)
            async let backendInstalledCommitTask = repositoryCommit(at: backendDirectory)
            let (remoteCommit, installedCommit, backendRemoteCommit, backendInstalledCommit, publishedBuild) =
                try await (
                    remoteCommitTask,
                    installedCommitTask,
                    backendRemoteCommitTask,
                    backendInstalledCommitTask,
                    publishedBuildTask
                )

            self.publishedBuild = publishedBuild
            self.installedCommit = installedCommit
            self.backendRemoteCommit = backendRemoteCommit
            self.backendDirectory = backendDirectory
            backendNeedsUpdate = backendRemoteCommit != backendInstalledCommit
            state = Self.availability(
                installed: installedCommit, remote: remoteCommit,
                published: publishedBuild?.commit, backendNeedsUpdate: backendNeedsUpdate
            )
            frontendNeedsUpdate = state == .updateAvailable && remoteCommit != installedCommit
            if completionPending && state == .current { state = .updateAvailable }
        } catch {
            state = .idle
            errorMessage = error.localizedDescription
        }
    }

    /// Only the published build of the current main commit is installable.
    /// While its archive is pending, hold the combined frontend/backend update.
    nonisolated static func availability(
        installed: String, remote: String, published: String?, backendNeedsUpdate: Bool
    ) -> State {
        if remote != installed {
            return published == remote ? .updateAvailable : .waitingForBuild
        }
        return backendNeedsUpdate ? .updateAvailable : .current
    }

    func installUpdate(restartBackend: @MainActor () async throws -> Void) async {
        // The release build can finish while an old "Update" button is still
        // on screen. Refresh before downloading so a stale button becomes the
        // current-version label instead of trying to rebuild the same commit.
        await checkForUpdates()
        guard updateAvailable else { return }

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
            if backendNeedsUpdate {
                progress = 0.05
                progressLabel = "Updating JasonPython…"
                try await updateBackendCheckout()
                backendNeedsUpdate = false
                completionPending = true
            }

            if frontendNeedsUpdate {
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

            }

            completionPending = true
            let appURL = Self.relaunchTarget(
                frontendUpdated: frontendNeedsUpdate, runningAppURL: Bundle.main.bundleURL
            )
            try await finishUpdate(appURL: appURL, restartBackend: restartBackend) { url in
                try self.scheduleSingleInstanceRelaunch(appURL: url)
                NSApplication.shared.terminate(nil)
            }
            completionPending = false
        } catch {
            if fileManager.fileExists(atPath: stagedAppURL.path) {
                try? fileManager.removeItem(at: stagedAppURL)
            }
            if let oldAppBackupURL, fileManager.fileExists(atPath: oldAppBackupURL.path) {
                try? fileManager.removeItem(at: Self.installedAppURL)
                try? fileManager.moveItem(at: oldAppBackupURL, to: Self.installedAppURL)
            }
            try? fileManager.removeItem(at: updateRoot)
            state = .updateAvailable
            progress = 0
            progressLabel = ""
            errorMessage = error.localizedDescription
        }
    }

    /// The backend must be ready before the UI exits, including backend-only updates.
    func finishUpdate(
        appURL: URL,
        restartBackend: @MainActor () async throws -> Void,
        relaunch: @MainActor (URL) throws -> Void
    ) async throws {
        progress = 0.92
        progressLabel = "Restarting server…"
        try await restartBackend()
        progress = 1.0
        progressLabel = "Relaunching…"
        try relaunch(appURL)
    }

    nonisolated static func relaunchTarget(frontendUpdated: Bool, runningAppURL: URL) -> URL {
        // A backend-only update must reopen the running local build, not an older installed app.
        frontendUpdated ? installedAppURL : runningAppURL
    }

    /// Install the published archive selected during the availability check.
    private func preparePackagedApp(in updateRoot: URL) async throws -> URL {
        progress = 0.10
        progressLabel = "Downloading…"
        return try await downloadPackagedApp(into: updateRoot)
    }

    private func downloadPackagedApp(into updateRoot: URL) async throws -> URL {
        guard let publishedBuild, let asset = publishedBuild.release.appArchive else {
            throw UpdatePreparationError(
                message: "The update is not published yet. Please check again shortly."
            )
        }

        var request = URLRequest(url: asset.browserDownloadURL)
        request.setValue("JasonApp/1.0", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await session.download(for: request)
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

        guard Self.sourceCommit(of: appURL) == publishedBuild.commit,
              publishedBuild.commit != installedCommit else {
            throw UpdatePreparationError(
                message: "The downloaded app does not match the published update. Please check again shortly."
            )
        }
        return appURL
    }

    private func updateBackendCheckout() async throws {
        guard let backendDirectory else {
            throw UpdatePreparationError(
                message: "Could not find the local JasonPython repository. "
                    + "Run Install JasonApp.command again."
            )
        }

        let changes = try await Self.runCommand(
            executable: "/usr/bin/git",
            arguments: ["status", "--porcelain"],
            currentDirectory: backendDirectory
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard changes.isEmpty else {
            throw UpdatePreparationError(
                message: "JasonPython has local changes. Commit or stash them before updating."
            )
        }

        _ = try await Self.runCommand(
            executable: "/usr/bin/git",
            arguments: ["pull", "--ff-only", "origin", "main"],
            currentDirectory: backendDirectory
        )

        let installed = try await repositoryCommit(at: backendDirectory)
        if let backendRemoteCommit, installed != backendRemoteCommit {
            throw UpdatePreparationError(
                message: "JasonPython did not reach the latest remote commit after updating."
            )
        }
    }

    func fetchPublishedBuild() async throws -> PublishedBuild? {
        guard let release = try await fetchLatestRelease(), release.appArchive != nil else { return nil }
        // target_commitish can be the moving branch name; resolve the immutable tag instead.
        let tagURL = Self.frontendCommitURL.deletingLastPathComponent()
            .appendingPathComponent(release.tagName)
        let commit = try await fetchRemoteCommit(from: tagURL)
        return PublishedBuild(release: release, commit: commit)
    }

    private func fetchLatestRelease() async throws -> GitHubRelease? {
        var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("JasonApp/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 { return nil }
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

    private func scheduleSingleInstanceRelaunch(appURL: URL) throws {
        guard appURL.pathExtension == "app", FileManager.default.fileExists(atPath: appURL.path) else {
            throw UpdatePreparationError(message: "Could not locate the running app to reopen. Start JasonApp using scripts/run_local.sh.")
        }
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
            appURL.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private func fetchRemoteCommit(from url: URL) async throws -> String {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("JasonApp/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(GitHubCommit.self, from: data).sha
    }

    private func repositoryCommit(at directory: URL) async throws -> String {
        try await Self.runCommand(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "HEAD"],
            currentDirectory: directory
        ).trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func resolveBackendDirectory() throws -> URL {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        var candidates: [URL] = []

        if let savedPath = UserDefaults.standard.string(forKey: Self.backendDirectoryKey) {
            candidates.append(URL(fileURLWithPath: savedPath, isDirectory: true))
        }
        if let frontendPath = UserDefaults.standard.string(forKey: Self.frontendDirectoryKey) {
            candidates.append(
                URL(fileURLWithPath: frontendPath, isDirectory: true)
                    .deletingLastPathComponent()
                    .appendingPathComponent("JasonPython", isDirectory: true)
            )
        }
        candidates += [
            homeDirectory.appendingPathComponent("JasonApp/JasonPython", isDirectory: true),
            homeDirectory.appendingPathComponent("Workspace/JasonPython", isDirectory: true),
            homeDirectory.appendingPathComponent("Developer/JasonPython", isDirectory: true),
        ]

        guard let directory = Self.validBackendDirectory(in: candidates) else {
            throw UpdatePreparationError(
                message: "Could not find the local JasonPython repository. "
                    + "Run Install JasonApp.command again."
            )
        }
        UserDefaults.standard.set(directory.path, forKey: Self.backendDirectoryKey)
        return directory
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

    nonisolated static func validBackendDirectory(in candidates: [URL]) -> URL? {
        let fileManager = FileManager.default
        for candidate in candidates {
            let directory = candidate.standardizedFileURL.resolvingSymlinksInPath()
            let gitDirectory = directory.appendingPathComponent(".git")
            let startupScript = directory.appendingPathComponent("scripts/run_local.sh")
            if fileManager.fileExists(atPath: gitDirectory.path),
               fileManager.isExecutableFile(atPath: startupScript.path) {
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
