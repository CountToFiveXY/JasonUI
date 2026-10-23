import AppKit
import SwiftUI

/// Shares ~/Documents/JasonApp/FileTransfer through the JasonPython backend,
/// so devices on the same network can download its files from a browser,
/// and upload to it when the host allows.
struct FileTransferView: View {
    @Environment(AppModel.self) private var model
    @State private var status: FileTransferStatus?
    @State private var allowUploads = false
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
                        Button("Start Sharing") {
                            Task { await perform { [allowUploads] in try await $0.startFileTransfer(allowUploads: allowUploads) } }
                        }
                            .buttonStyle(.borderedProminent)
                            .disabled(isWorking)
                    }
                    if isWorking { ProgressView().controlSize(.small) }
                }
                Toggle("Allow devices to upload files", isOn: Binding(
                    get: { allowUploads },
                    set: { value in
                        allowUploads = value
                        // While sharing, apply the change right away.
                        if status?.running == true {
                            Task { await perform { try await $0.startFileTransfer(allowUploads: value) } }
                        }
                    }
                ))
                .disabled(isWorking)
                if status?.running == true, let code = status?.uploadCode {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Upload code")
                        Spacer()
                        Text(code)
                            .font(.system(.title, design: .monospaced).bold())
                            .kerning(4)
                            .textSelection(.enabled)
                    }
                    Text("Devices enter this code once before they can upload. It is the same on every Mac; a changed code applies the next time uploads are turned on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if status?.running == true {
                    if let address = status?.url, let url = URL(string: address) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(address)
                                .font(.system(.title3, design: .monospaced))
                                .textSelection(.enabled)
                            Text(status?.hostName == nil
                                 ? "Type this address in a browser on another device."
                                 : "Type this address in a browser on any device. It stays the same whichever Mac is sharing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Button(didCopyAddress ? "Copied" : "Copy Address") {
                                    NSPasteboard.general.clearContents()
                                    didCopyAddress = NSPasteboard.general.setString(address, forType: .string)
                                }
                                Link("Open Download Page", destination: url)
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
                    if status.files.isEmpty {
                        Text("No files yet. Add files to the folder to share them.")
                            .foregroundStyle(.secondary)
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
                        Text("\(status.files.count) shared files")
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

    private func apply(_ newStatus: FileTransferStatus) {
        if newStatus.url != status?.url { didCopyAddress = false }
        // While sharing, the switch shows what the server is actually doing.
        if newStatus.running { allowUploads = newStatus.allowUploads }
        status = newStatus
    }

    private func openFolder(_ path: String) {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
