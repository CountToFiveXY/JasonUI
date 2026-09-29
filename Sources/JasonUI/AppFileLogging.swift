import Darwin
import Foundation

enum AppFileLogging {
    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/JasonApp", isDirectory: true)
    }

    static var frontendLogURL: URL {
        directoryURL.appendingPathComponent("frontend.log")
    }

    static var backendLogURL: URL {
        directoryURL.appendingPathComponent("backend.log")
    }

    private static var legacyBackendLogURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/JasonApp/services.log")
    }

    static func redirectFrontendOutput() {
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            if !fileManager.fileExists(atPath: backendLogURL.path),
               fileManager.fileExists(atPath: legacyBackendLogURL.path) {
                try fileManager.copyItem(at: legacyBackendLogURL, to: backendLogURL)
            }
            if !fileManager.fileExists(atPath: frontendLogURL.path) {
                guard fileManager.createFile(
                    atPath: frontendLogURL.path,
                    contents: nil
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }

            let handle = try FileHandle(forWritingTo: frontendLogURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n--- JasonApp launch \(Date()) ---\n".utf8))
            try handle.synchronize()

            guard dup2(handle.fileDescriptor, STDOUT_FILENO) != -1,
                  dup2(handle.fileDescriptor, STDERR_FILENO) != -1 else {
                throw POSIXError(.EBADF)
            }
            setvbuf(stdout, nil, _IOLBF, 0)
            setvbuf(stderr, nil, _IONBF, 0)
        } catch {
            fputs("Could not configure JasonApp file logging: \(error)\n", stderr)
        }
    }
}
