import Foundation
import Testing
@testable import JasonUI

struct AppModelTests {
    @Test func storesLogsInTheDocumentsFolder() {
        let expectedDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/JasonApp", isDirectory: true)

        #expect(AppFileLogging.directoryURL == expectedDirectory)
        #expect(AppFileLogging.frontendLogURL.lastPathComponent == "frontend.log")
        #expect(AppFileLogging.backendLogURL.lastPathComponent == "backend.log")
    }

    @Test func formatsAppReleaseLabel() {
        #expect(AppUpdateManager.releaseLabel(for: "1.0") == "v1.0")
        #expect(AppUpdateManager.releaseLabel(for: "v2.3.4") == "v2.3.4")
        #expect(AppUpdateManager.releaseLabel(for: nil) == "v—")
    }

    @Test func findsExecutableBackendStartupScript() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("JasonApp-AppModelTests-\(UUID().uuidString)", isDirectory: true)
        let invalidDirectory = testRoot.appendingPathComponent("invalid", isDirectory: true)
        let validDirectory = testRoot.appendingPathComponent("JasonPython", isDirectory: true)
        let scriptsDirectory = validDirectory.appendingPathComponent("scripts", isDirectory: true)
        let startupScript = scriptsDirectory.appendingPathComponent("run_local.sh")
        defer { try? fileManager.removeItem(at: testRoot) }

        try fileManager.createDirectory(at: invalidDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        #expect(fileManager.createFile(atPath: startupScript.path, contents: Data("#!/bin/sh\n".utf8)))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: startupScript.path)

        let result = AppModel.validBackendDirectory(in: [invalidDirectory, validDirectory])
        #expect(result == validDirectory.standardizedFileURL.resolvingSymlinksInPath())
    }

    @Test func findsFrontendGitRepository() throws {
        let fileManager = FileManager.default
        let testRoot = fileManager.temporaryDirectory
            .appendingPathComponent("JasonApp-UpdateTests-\(UUID().uuidString)", isDirectory: true)
        let invalidDirectory = testRoot.appendingPathComponent("invalid", isDirectory: true)
        let validDirectory = testRoot.appendingPathComponent("JasonUI", isDirectory: true)
        defer { try? fileManager.removeItem(at: testRoot) }

        try fileManager.createDirectory(at: invalidDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: validDirectory.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        #expect(
            fileManager.createFile(
                atPath: validDirectory.appendingPathComponent("Package.swift").path,
                contents: Data()
            )
        )

        let result = AppUpdateManager.validFrontendDirectory(
            in: [invalidDirectory, validDirectory]
        )
        #expect(result == validDirectory.standardizedFileURL.resolvingSymlinksInPath())
    }

    @Test func givesGoogleCloudLoginHelpForMissingCredentials() {
        let detail = AppModel.googleCloudFailureDetail(
            for: "Firestore credentials are not configured."
        )
        #expect(detail == "Not authenticated. Run: gcloud auth application-default login")
    }

    @Test func preservesOtherGoogleCloudConnectionErrors() {
        let detail = AppModel.googleCloudFailureDetail(for: "The network connection was lost.")
        #expect(detail == "The network connection was lost.")
    }
}

struct AppUpdateTests {
    @Test func picksThePackagedAppFromTheReleaseAssets() throws {
        let json = Data(#"""
        {"tag_name":"build-42","assets":[
          {"name":"notes.md","browser_download_url":"https://example.com/notes.md"},
          {"name":"JasonApp.zip","browser_download_url":"https://example.com/JasonApp.zip","state":"uploaded","size":1024}
        ]}
        """#.utf8)

        let release = try JSONDecoder().decode(AppUpdateManager.GitHubRelease.self, from: json)

        #expect(release.tagName == "build-42")
        let archive = try #require(release.appArchive)
        #expect(archive.browserDownloadURL.absoluteString == "https://example.com/JasonApp.zip")
    }

    @Test func readsTheCommitAnAppBundleWasBuiltFrom() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("JasonApp-ReleaseTests-\(UUID().uuidString)", isDirectory: true)
        let appURL = root.appendingPathComponent("JasonApp.app/Contents", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: appURL, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["JasonSourceCommit": "abc1234"],
            format: .xml,
            options: 0
        )
        try plist.write(to: appURL.appendingPathComponent("Info.plist"))

        let commit = AppUpdateManager.sourceCommit(
            of: root.appendingPathComponent("JasonApp.app", isDirectory: true)
        )
        #expect(commit == "abc1234")
    }

    @Test func reportsNoCommitForABundleWithoutAPlist() {
        let missing = URL(fileURLWithPath: "/nonexistent/JasonApp.app")
        #expect(AppUpdateManager.sourceCommit(of: missing) == nil)
    }

    @Test func findsBackendGitRepositoryForUpdates() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("JasonApp-BackendUpdateTests-\(UUID().uuidString)")
        let backend = root.appendingPathComponent("JasonPython")
        let script = backend.appendingPathComponent("scripts/run_local.sh")
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(
            at: backend.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: script.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        #expect(fileManager.createFile(atPath: script.path, contents: Data("#!/bin/sh\n".utf8)))
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        #expect(
            AppUpdateManager.validBackendDirectory(in: [root, backend])
                == backend.standardizedFileURL.resolvingSymlinksInPath()
        )
    }
}

@MainActor
struct InvoiceImageRendererTests {
    @Test func rendersABillWithoutTheBrandImage() {
        // The brand image is decoration. Rendering must not depend on finding
        // it — looking for it used to bring the app down.
        let records = [
            ExpenseRecord(id: UUID().uuidString, purpose: "Track pass", amountInCents: 12_50, createdAt: Date()),
            ExpenseRecord(id: UUID().uuidString, purpose: "Fuel", amountInCents: 4_099, createdAt: Date()),
        ]

        let image = InvoiceImageRenderer.makeImage(records: records)

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test func rendersAnEmptyBill() {
        let image = InvoiceImageRenderer.makeImage(records: [])
        #expect(image.size.width > 0)
    }

    @Test func brandImageLookupNeverTraps() {
        // Returns a URL when packaged and nil when not, but must not crash.
        _ = InvoiceImageRenderer.brandImageURL()
    }
}
