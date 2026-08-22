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
                ServiceStatusRow(title: "Backend Server", state: model.backendState)
                ServiceStatusRow(title: "Redis", state: model.redisState)
                ServiceStatusRow(title: "Temporal", state: model.temporalState)
                HStack {
                    Spacer()
                    Button("Check All Services") { Task { await model.checkConnection() } }
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

}

private struct ServiceStatusRow: View {
    let title: String
    let state: AppModel.ServiceState

    var body: some View {
        HStack(spacing: 8) {
            indicator
            Text(title)
            Spacer()
            Text(detail).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var indicator: some View {
        switch state {
        case .checking:
            ProgressView().controlSize(.small).frame(width: 16)
        case .running:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .unavailable:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .unsupported:
            Image(systemName: "questionmark.circle.fill").foregroundStyle(.secondary)
        case .unknown:
            Image(systemName: "circle").foregroundStyle(.secondary)
        }
    }

    private var detail: String {
        switch state {
        case .unknown: "Not checked"
        case .checking: "Checking…"
        case let .running(message): message ?? "Running"
        case let .unavailable(message): message ?? "Unavailable"
        case .unsupported: "Check not supported"
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
    @State private var isURLFieldFocused = false

    var body: some View {
        Form {
            Section("Create a short URL") {
                HStack {
                    HStack(spacing: 10) {
                        Text("👉")
                            .font(.title3)
                        LeftAlignedTextField(
                            placeholder: "Enter URL",
                            text: $longURL,
                            isFocused: $isURLFieldFocused
                        )
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(nsColor: .textBackgroundColor))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isURLFieldFocused ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
                    }
                    .environment(\.layoutDirection, .leftToRight)
                    Button("Shorten") { Task { await shorten() } }
                        .disabled(longURL.isEmpty || isLoading)
                }
            }
            if let resultURL {
                Section("Generated Link") {
                    Text(resultURL.absoluteString)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                    Button("Copy Generated Link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(resultURL.absoluteString, forType: .string)
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
        do {
            let response = try await client.shorten(url: longURL)
            resultURL = client.shortURL(for: response.shortUrl)
            error = nil
        }
        catch { self.error = error.localizedDescription }
    }
}

struct RankingView: View {
    @Environment(AppModel.self) private var model
    @State private var total = 100
    @State private var type = CardType.ch
    @State private var car = "Galaxy"
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var error: String?
    @State private var didCopy = false

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            Form {
                TextField("Participants", value: $total, format: .number)
                Picker("Event Type", selection: $type) {
                    ForEach(CardType.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("Car", text: $car)
                HStack {
                    Spacer()
                    Button("Generate") { Task { await generate() } }
                        .disabled(total < 1 || car.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
                ErrorSection(message: error)
            }
            .formStyle(.grouped)
            .frame(width: 420)
            if let image {
                VStack(spacing: 12) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 228, maxHeight: 380)
                        .shadow(radius: 8)
                    Button {
                        copyImage(image)
                    } label: {
                        Text(didCopy ? "Copied" : "Copy")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(width: 228)
                }
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
            image = preview
            didCopy = false
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func copyImage(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        didCopy = NSPasteboard.general.writeObjects([image])
    }
}

struct WorkflowsView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var response: WorkflowResponse?
    @State private var isLoading = false
    @State private var error: String?
    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        Form {
            Section("Temporal") {
                Button("Run Hello Workflow") { Task { await run { try await $0.hello() } } }
                HStack {
                    Button("Run Greeting") { Task { await run { try await $0.greeting(name: name) } } }
                        .disabled(name.isEmpty)
                    Spacer()
                    ClickToEnterField(
                        prompt: "Enter your name",
                        text: $name,
                        isFocused: $isNameFieldFocused
                    )
                }
            }
            if let response {
                Section("Result") {
                    LabeledContent("Message", value: response.result)
                    LabeledContent("Workflow ID") {
                        if let url = model.client?.temporalWorkflowURL(workflowID: response.workflowID) {
                            Link(response.workflowID, destination: url)
                                .help("Open this workflow in Temporal UI")
                        } else {
                            Text(response.workflowID).textSelection(.enabled)
                        }
                    }
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

private struct LeftAlignedTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.alignment = .left
        field.baseWritingDirection = .leftToRight
        field.cell?.alignment = .left
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder
        field.alignment = .left
        field.baseWritingDirection = .leftToRight
        field.cell?.alignment = .left
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            _text = text
            _isFocused = isFocused
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isFocused = true
            if let editor = (notification.object as? NSTextField)?.currentEditor() {
                editor.alignment = .left
                editor.baseWritingDirection = .leftToRight
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isFocused = false
        }
    }
}

private struct ClickToEnterField: View {
    let prompt: String
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var textAlignment: TextAlignment = .trailing
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: textAlignment == .leading ? .leading : .trailing) {
            TextField("", text: $text)
                .focused(isFocused)
                .multilineTextAlignment(textAlignment)

            if text.isEmpty && !isFocused.wrappedValue {
                Text(prompt)
                    .foregroundStyle(isHovering ? Color.accentColor : .secondary)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { isFocused.wrappedValue = true }
                    .onHover { isHovering = $0 }
            }
        }
        .frame(minWidth: 260)
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
