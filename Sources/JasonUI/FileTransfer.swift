import AppKit
import SwiftUI

/// Shares ~/Documents/JasonApp/FileTransfer through the JasonPython backend,
/// so devices on the same network can download its files from a browser,
/// and upload to it when the host allows.
struct FileTransferView: View {
    @Environment(AppModel.self) private var model
    @State private var status: FileTransferStatus?
    @State private var allowUploads = false
    @State private var requireCode = false
    @State private var isWorking = false
    @State private var didCopyAddress = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Share on this network") {
                HStack {
                    if status?.running == true {
                        Label("Sharing", systemImage: "circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Stop Sharing") { Task { await perform { try await $0.stopFileTransfer() } } }
                            .disabled(isWorking)
                    } else {
                        Text("Devices on the same Wi-Fi or local network can download these files.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Start Sharing") { Task { await applySwitches() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(isWorking)
                    }
                    if isWorking { ProgressView().controlSize(.small) }
                }
                Toggle("Allow devices to upload files", isOn: Binding(
                    get: { allowUploads },
                    set: { value in
                        allowUploads = value
                        if status?.running == true { Task { await applySwitches() } }
                    }
                ))
                .disabled(isWorking)
                Toggle("Require code", isOn: Binding(
                    get: { requireCode },
                    set: { value in
                        requireCode = value
                        if status?.running == true { Task { await applySwitches() } }
                    }
                ))
                .disabled(isWorking)
                if status?.running == true {
                    if let address = status?.url, let url = URL(string: address) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(address)
                                    .textSelection(.enabled)
                                Spacer()
                                Link("Open Download Page", destination: url)
                            }
                            Text(status?.hostName == nil
                                 ? "Type this address in a browser on another device."
                                 : "Type this address in a browser on any device. It stays the same whichever Mac is sharing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button(didCopyAddress ? "Copied" : "Copy Address") {
                                NSPasteboard.general.clearContents()
                                didCopyAddress = NSPasteboard.general.setString(address, forType: .string)
                            }
                            if status?.hostName != nil, let ipAddress = status?.ipURL {
                                Text("If a device can't open it (some Android phones), use \(ipAddress)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    } else {
                        Text("Connect this Mac to Wi-Fi or Ethernet so other devices can reach it.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let status {
                Section {
                    if status.files.isEmpty && status.folders.isEmpty {
                        Text("No files yet. Add files to the folder to share them.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(status.folders, id: \.self) { name in
                        HStack {
                            Image(systemName: "folder")
                            Text(name).lineLimit(1)
                            Spacer()
                            Text("Folder").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(status.files) { file in
                        HStack {
                            Image(systemName: "doc")
                            Text(file.name).lineLimit(1)
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    HStack {
                        Text(sharedSummary(status))
                        Spacer()
                        Button("Open Folder") { openFolder(status.folder) }
                    }
                } footer: {
                    Text(status.folder).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            ErrorSection(message: error)
        }
        .formStyle(.grouped)
        .navigationTitle("File Transfer")
        // Keep the file list current while this page is open.
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func refresh() async {
        guard !isWorking, let client = model.client else { return }
        do {
            apply(try await client.fileTransferStatus())
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func perform(_ action: (APIClient) async throws -> FileTransferStatus) async {
        guard let client = model.client else { error = APIError.invalidBaseURL.localizedDescription; return }
        isWorking = true; defer { isWorking = false }
        do {
            apply(try await action(client))
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Starts sharing with both switches, or applies them while sharing.
    private func applySwitches() async {
        await perform { [allowUploads, requireCode] in
            try await $0.startFileTransfer(allowUploads: allowUploads, requireCode: requireCode)
        }
        // A refused change, such as no code set in Firestore, leaves the
        // server as it was; show that rather than the switch just flipped.
        if error != nil, let status, status.running {
            allowUploads = status.allowUploads
            requireCode = status.requireCode
        }
    }

    private func apply(_ newStatus: FileTransferStatus) {
        if newStatus.url != status?.url { didCopyAddress = false }
        // While sharing, the switches show what the server is actually doing.
        if newStatus.running {
            allowUploads = newStatus.allowUploads
            requireCode = newStatus.requireCode
        }
        status = newStatus
    }

    private func sharedSummary(_ status: FileTransferStatus) -> String {
        let files = "\(status.files.count) shared files"
        return status.folders.isEmpty ? files : "\(status.folders.count) folders, \(files)"
    }

    private func openFolder(_ path: String) {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
