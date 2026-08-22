import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Feature = .dashboard

    var body: some View {
        NavigationSplitView {
            List(Feature.allCases, selection: $selection) { feature in
                Label(feature.title, systemImage: feature.icon)
                    .tag(feature)
            }
            .navigationTitle("Jason UI")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            Group {
                switch selection {
                case .dashboard: DashboardView()
                case .shortener: URLShortenerView()
                case .ranking: RankingView()
                case .workflows: WorkflowsView()
                case .image: ServerImageView()
                }
            }
            .padding(24)
        }
        .task { await model.checkConnection() }
    }
}

private enum Feature: String, CaseIterable, Identifiable {
    case dashboard, shortener, ranking, workflows, image
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: "Server"
        case .shortener: "URL Shortener"
        case .ranking: "Ranking Card"
        case .workflows: "Workflows"
        case .image: "Server Image"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: "server.rack"
        case .shortener: "link"
        case .ranking: "chart.bar.doc.horizontal"
        case .workflows: "point.3.connected.trianglepath.dotted"
        case .image: "photo"
        }
    }
}

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Backend") {
                TextField("Server URL", text: $model.serverAddress)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    status
                    Spacer()
                    Button("Check Connection") { Task { await model.checkConnection() } }
                        .disabled(model.isChecking)
                }
            }
            if let message = model.errorMessage {
                Section("Connection Error") { Text(message).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Server")
    }

    @ViewBuilder private var status: some View {
        if model.isChecking {
            ProgressView().controlSize(.small)
            Text("Checking…")
        } else if let health = model.health {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("\(health.status) · Redis \(health.redis)")
        } else {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            Text("Not connected")
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            TextField("Server URL", text: $model.serverAddress)
            Button("Test Connection") { Task { await model.checkConnection() } }
        }
    }
}

struct URLShortenerView: View {
    @Environment(AppModel.self) private var model
    @State private var longURL = ""
    @State private var resultURL: URL?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Create a short URL") {
                TextField("https://example.com/long/path", text: $longURL)
                Button("Shorten") { Task { await shorten() } }
                    .disabled(longURL.isEmpty || isLoading)
            }
            if let resultURL {
                Section("Result") {
                    Text(resultURL.absoluteString).textSelection(.enabled)
                    HStack {
                        Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(resultURL.absoluteString, forType: .string) }
                        Button("Open") { NSWorkspace.shared.open(resultURL) }
                    }
                }
            }
            ErrorSection(message: error)
        }
        .formStyle(.grouped)
        .navigationTitle("URL Shortener")
    }

    private func shorten() async {
        guard let client = model.client else { error = APIError.invalidBaseURL.localizedDescription; return }
        isLoading = true; defer { isLoading = false }
        do { resultURL = client.shortURL(for: try await client.shorten(url: longURL).shortKey); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct RankingView: View {
    @Environment(AppModel.self) private var model
    @State private var total = 100
    @State private var type = CardType.ch
    @State private var car = "Galaxy"
    @State private var image: NSImage?
    @State private var imageData: Data?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            Form {
                TextField("Car", text: $car)
                TextField("Participants", value: $total, format: .number)
                Picker("Card Type", selection: $type) {
                    ForEach(CardType.allCases) { Text($0.rawValue).tag($0) }
                }
                Button("Generate") { Task { await generate() } }
                    .disabled(total < 1 || car.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                if imageData != nil { Button("Save As…", action: saveImage) }
                ErrorSection(message: error)
            }
            .formStyle(.grouped)
            .frame(maxWidth: 420)
            if let image {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 304, maxHeight: 506)
                    .shadow(radius: 8)
            } else {
                ContentUnavailableView("No Ranking Card", systemImage: "photo", description: Text("Generate a card to preview it."))
            }
        }
        .navigationTitle("Ranking Card")
    }

    private func generate() async {
        guard let client = model.client else { error = APIError.invalidBaseURL.localizedDescription; return }
        isLoading = true; defer { isLoading = false }
        do {
            let data = try await client.ranking(total: total, type: type, car: car)
            guard let preview = NSImage(data: data) else { throw APIError.invalidResponse }
            imageData = data; image = preview; error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func saveImage() {
        guard let imageData else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "ranking.png"
        if panel.runModal() == .OK, let url = panel.url { try? imageData.write(to: url) }
    }
}

struct WorkflowsView: View {
    @Environment(AppModel.self) private var model
    @State private var name = "Jason"
    @State private var response: WorkflowResponse?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Temporal") {
                Button("Run Hello Workflow") { Task { await run { try await $0.hello() } } }
                HStack {
                    TextField("Name", text: $name)
                    Button("Run Greeting") { Task { await run { try await $0.greeting(name: name) } } }
                        .disabled(name.isEmpty)
                }
            }
            if let response {
                Section("Result") {
                    LabeledContent("Message", value: response.result)
                    LabeledContent("Workflow ID", value: response.workflowID).textSelection(.enabled)
                }
            }
            ErrorSection(message: error)
        }
        .formStyle(.grouped)
        .disabled(isLoading)
        .navigationTitle("Workflows")
    }

    private func run(_ operation: (APIClient) async throws -> WorkflowResponse) async {
        guard let client = model.client else { error = APIError.invalidBaseURL.localizedDescription; return }
        isLoading = true; defer { isLoading = false }
        do { response = try await operation(client); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct ServerImageView: View {
    @Environment(AppModel.self) private var model
    @State private var image: NSImage?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            HStack { Button("Load Image") { Task { await load() } }; Spacer() }
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { ContentUnavailableView("No Image Loaded", systemImage: "photo") }
            ErrorSection(message: error)
        }
        .navigationTitle("Server Image")
    }

    private func load() async {
        guard let client = model.client else { error = APIError.invalidBaseURL.localizedDescription; return }
        do {
            let data = try await client.displayImage()
            guard let loaded = NSImage(data: data) else { throw APIError.invalidResponse }
            image = loaded; error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct ErrorSection: View {
    let message: String?
    var body: some View {
        if let message { Section("Error") { Text(message).foregroundStyle(.red) } }
    }
}

