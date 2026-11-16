import Foundation
import Testing
@testable import JasonUI

@MainActor
@Suite(.serialized)
struct AppUpdateAvailabilityTests {
    @Test func enablesUpdateForANewerPublishedPackage() {
        #expect(AppUpdateManager.availability(
            installed: "installed", published: "published", backendNeedsUpdate: false
        ) == .updateAvailable)
    }

    @Test func currentPublishedPackageOnlyUpdatesForBackendChanges() {
        #expect(AppUpdateManager.availability(
            installed: "published", published: "published", backendNeedsUpdate: false
        ) == .current)
        #expect(AppUpdateManager.availability(
            installed: "published", published: "published", backendNeedsUpdate: true
        ) == .updateAvailable)
    }

    @Test func localDevelopmentBuildIgnoresPublishedFrontendButStillUpdatesBackend() {
        #expect(AppUpdateManager.availability(
            installed: "local", published: "published", frontendUpdatesEnabled: false,
            backendNeedsUpdate: false
        ) == .current)
        #expect(AppUpdateManager.availability(
            installed: "local", published: "published", frontendUpdatesEnabled: false,
            backendNeedsUpdate: true
        ) == .updateAvailable)
    }

    @Test func onlyInstalledApplicationEnablesFrontendReplacement() {
        #expect(AppUpdateManager.frontendUpdatesEnabled(
            runningAppURL: URL(fileURLWithPath: "/Applications/JasonApp.app")
        ))
        #expect(!AppUpdateManager.frontendUpdatesEnabled(
            runningAppURL: URL(fileURLWithPath: "/tmp/JasonUI/.build/app-package/JasonApp.app")
        ))
    }

    @Test func usesImmutableReleaseTargetWithoutACommitRequest() async throws {
        ReleaseURLProtocol.handler = { request in
            #expect(request.url?.path == "/repos/CountToFiveXY/JasonUI/releases/latest")
            return (200, Self.releaseJSON())
        }
        let build = try #require(try await manager().fetchPublishedBuild())
        #expect(build.commit == String(repeating: "a", count: 40))
        #expect(build.release.appArchive?.browserDownloadURL.absoluteString == "https://example.com/JasonApp.zip")
    }

    @Test func rejectsReleaseWithoutImmutableCommit() async {
        ReleaseURLProtocol.handler = { _ in
            (200, Self.releaseJSON(targetCommitish: "main"))
        }
        await #expect(throws: (any Error).self) {
            _ = try await manager().fetchPublishedBuild()
        }
    }

    @Test func rejectsIncompleteOrNonpublicReleases() async throws {
        let invalid = [
            Self.releaseJSON(assets: []),
            Self.releaseJSON(state: "new"),
            Self.releaseJSON(size: 0),
            Self.releaseJSON(draft: true),
            Self.releaseJSON(prerelease: true),
        ]
        for payload in invalid {
            ReleaseURLProtocol.handler = { request in
                #expect(request.url?.path == "/repos/CountToFiveXY/JasonUI/releases/latest")
                return (200, payload)
            }
            let build = try await manager().fetchPublishedBuild()
            #expect(build == nil)
        }
    }

    @Test func missingReleaseIsPendingButNetworkErrorsAreNotHidden() async throws {
        ReleaseURLProtocol.handler = { _ in (404, Data()) }
        let build = try await manager().fetchPublishedBuild()
        #expect(build == nil)
        ReleaseURLProtocol.handler = { _ in (403, Data()) }
        await #expect(throws: (any Error).self) {
            _ = try await manager().fetchPublishedBuild()
        }
    }

    @Test func restartsBackendBeforeReopeningTheUI() async throws {
        let updater = manager()
        let currentApp = URL(fileURLWithPath: "/tmp/local build/JasonApp.app")
        var events: [String] = []
        try await updater.finishUpdate(appURL: currentApp) {
            #expect(updater.progressLabel == "Restarting server…")
            events.append("restart")
            await Task.yield()
            events.append("healthy")
        } relaunch: { appURL in
            #expect(appURL == currentApp)
            #expect(updater.progressLabel == "Relaunching…")
            events.append("reopen")
        }
        #expect(events == ["restart", "healthy", "reopen"])
    }

    @Test func failedBackendRestartDoesNotCloseOrReopenUI() async {
        let updater = manager()
        var reopened = false
        await #expect(throws: URLError.self) {
            try await updater.finishUpdate(appURL: URL(fileURLWithPath: "/tmp/JasonApp.app")) {
                throw URLError(.cannotConnectToHost)
            } relaunch: { _ in
                reopened = true
            }
        }
        #expect(!reopened)
        #expect(updater.progressLabel == "Restarting server…")
    }

    @Test func backendOnlyUpdateKeepsCurrentUIAndFrontendUpdateUsesInstalledApp() {
        let localBuild = URL(fileURLWithPath: "/tmp/checkout/.build/app-package/JasonApp.app")
        #expect(AppUpdateManager.relaunchTarget(frontendUpdated: false, runningAppURL: localBuild) == localBuild)
        #expect(AppUpdateManager.relaunchTarget(frontendUpdated: true, runningAppURL: localBuild).path == "/Applications/JasonApp.app")
    }

    private func manager() -> AppUpdateManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseURLProtocol.self]
        return AppUpdateManager(session: URLSession(configuration: configuration))
    }

    nonisolated private static func releaseJSON(
        state: String = "uploaded", size: Int = 1024,
        draft: Bool = false, prerelease: Bool = false, assets: [[String: Any]]? = nil,
        targetCommitish: String = String(repeating: "a", count: 40)
    ) -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "tag_name": "build-42", "target_commitish": targetCommitish,
            "draft": draft, "prerelease": prerelease,
            "assets": assets ?? [[
                "name": "JasonApp.zip", "browser_download_url": "https://example.com/JasonApp.zip",
                "state": state, "size": size,
            ]],
        ])
    }
}

private final class ReleaseURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
