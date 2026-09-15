import Foundation
import Testing
@testable import JasonUI

struct AppModelTests {
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
}

struct AppUpdateTests {
    @Test func picksThePackagedAppFromTheReleaseAssets() throws {
        let json = Data(#"""
        {"tag_name":"build-42","assets":[
          {"name":"notes.md","browser_download_url":"https://example.com/notes.md"},
          {"name":"JasonApp.zip","browser_download_url":"https://example.com/JasonApp.zip"}
        ]}
        """#.utf8)

        let release = try JSONDecoder().decode(ReleaseFeedProbe.self, from: json)

        #expect(release.tagName == "build-42")
        let archive = try #require(release.assets.first { $0.name == AppUpdateManager.releaseAssetName })
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
}

/// Mirrors the release feed shape AppUpdateManager decodes, which is private.
private struct ReleaseFeedProbe: Decodable {
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
}

struct CardTypeTests {
    /// Pinned to the backend's PERCENTAGES, which owns these values. If the
    /// backend's own test changes, this one has to change with it.
    @Test func summarisesThePercentageRowsPerEventType() {
        #expect(CardType.ch.percentageSummary == "1/5/25/50/75/100")
        #expect(CardType.sp.percentageSummary == "1/10/25/50/75/100")
        #expect(CardType.se.percentageSummary == "5/10/25/50/75/100")
    }

    @Test func everyEventTypeHasSixRows() {
        for type in CardType.allCases {
            #expect(type.percentages.count == 6, "\(type.displayName)")
            #expect(type.percentages.last == 100, "\(type.displayName)")
            #expect(type.percentages == type.percentages.sorted(), "\(type.displayName)")
        }
    }
}

@MainActor
struct InvoiceImageRendererTests {
    @Test func rendersABillWithoutTheBrandImage() {
        // The brand image is decoration. Rendering must not depend on finding
        // it — looking for it used to bring the app down.
        let records = [
            ExpenseRecord(id: UUID(), purpose: "Track pass", amountInCents: 12_50, createdAt: Date()),
            ExpenseRecord(id: UUID(), purpose: "Fuel", amountInCents: 4_099, createdAt: Date()),
        ]

        let image = InvoiceImageRenderer.makeImage(records: records, currencyCode: "USD")

        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test func rendersAnEmptyBill() {
        let image = InvoiceImageRenderer.makeImage(records: [], currencyCode: "USD")
        #expect(image.size.width > 0)
    }

    @Test func brandImageLookupNeverTraps() {
        // Returns a URL when packaged and nil when not, but must not crash.
        _ = InvoiceImageRenderer.brandImageURL()
    }
}
