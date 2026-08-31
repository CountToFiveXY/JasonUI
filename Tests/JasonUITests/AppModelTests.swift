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
}
