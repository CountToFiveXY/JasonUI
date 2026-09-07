import AppKit
import SwiftUI
import WebKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Feature = .dashboard
    @State private var updateManager = AppUpdateManager()

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(Feature.allCases, selection: $selection) { feature in
                    Label(feature.title, systemImage: feature.icon)
                        .tag(feature)
                }
                Divider()
                GitHubFooter(updateManager: updateManager)
            }
            .navigationTitle("JasonApp")
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            Group {
                switch selection {
                case .dashboard: DashboardView()
                case .shortener: URLShortenerView()
                case .ranking: RankingView()
                case .workflows: WorkflowsView()
                case .quickLink: QuickLinkView()
                }
            }
            .padding(24)
        }
        .task { await model.checkConnection() }
        .task { await updateManager.monitorForUpdates() }
    }
}

private struct GitHubFooter: View {
    let updateManager: AppUpdateManager
    private let repositoriesURL = URL(string: "https://github.com/CountToFiveXY?tab=repositories")!

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 7) {
                Link(destination: repositoriesURL) {
                    HStack(spacing: 7) {
                        if let iconURL = Bundle.main.url(forResource: "GitHubMark", withExtension: "png"),
                           let icon = NSImage(contentsOf: iconURL) {
                            Image(nsImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                        }
                        Text("GitHub")
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 4)
                updateControl
            }

            if let errorMessage = updateManager.errorMessage {
                CopyableErrorText(message: errorMessage)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var updateControl: some View {
        if updateManager.isUpdating {
            VStack(alignment: .trailing, spacing: 3) {
                ProgressView(value: updateManager.progress)
                    .frame(width: 86)
                Text(updateManager.progressLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if updateManager.updateAvailable {
            Button("Update") {
                Task { await updateManager.installUpdate() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button {
                Task { await updateManager.checkForUpdates() }
            } label: {
                HStack(spacing: 5) {
                    if updateManager.isChecking {
                        ProgressView().controlSize(.small)
                    }
                    Text(updateManager.isChecking ? "Checking" : updateManager.releaseLabel)
                }
            }
            .controlSize(.small)
            .disabled(updateManager.isChecking)
        }
    }
}

private enum Feature: String, CaseIterable, Identifiable {
    case dashboard, shortener, ranking, workflows, quickLink
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: "Server"
        case .shortener: "URL Shortener"
        case .ranking: "Ranking Card"
        case .workflows: "Workflows"
        case .quickLink: "Quick Links"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: "server.rack"
        case .shortener: "link"
        case .ranking: "chart.bar.doc.horizontal"
        case .workflows: "point.3.connected.trianglepath.dotted"
        case .quickLink: "link.circle"
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
                    Button("Check Connection") {
                        Task { await model.checkConnection() }
                    }
                    .disabled(model.isChecking || model.isActivating || model.isClosing)
                    Button(model.isActivating ? "Activating…" : "Activate All Services") {
                        Task { await model.activateAllServices() }
                    }
                    .disabled(model.isChecking || model.isActivating || model.isClosing)
                    Button(model.isClosing ? "Closing…" : "Close Server", role: .destructive) {
                        Task { await model.closeServer() }
                    }
                    .disabled(model.isChecking || model.isActivating || model.isClosing)
                }
            }
            if let message = model.errorMessage {
                Section("Connection Error") { CopyableErrorText(message: message) }
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
            Text(detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
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

    var body: some View {
        Form {
            Section("Create a short URL") {
                HStack {
                    RoundedEntryField(placeholder: "Enter URL", text: $longURL)
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
    @State private var totalText = ""
    @State private var type = CardType.ch
    @State private var car = ""
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var error: String?
    @State private var didCopy = false
    @State private var isTotalFieldFocused = false
    @State private var isCarFieldFocused = false

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            Form {
                LabeledContent("Participant") {
                    NativeTextField(
                        placeholder: "Enter Total Participants",
                        text: $totalText,
                        isFocused: $isTotalFieldFocused,
                        alignment: .right
                    )
                    .frame(width: 260)
                }
                Picker("Event Type", selection: $type) {
                    ForEach(CardType.allCases) { Text($0.displayName).tag($0) }
                }
                LabeledContent("Car Name") {
                    NativeTextField(
                        placeholder: "Enter Car",
                        text: $car,
                        isFocused: $isCarFieldFocused,
                        alignment: .right
                    )
                    .frame(width: 260)
                }
                HStack {
                    Spacer()
                    Button("Generate") { Task { await generate() } }
                        .disabled(validTotal == nil || car.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
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
        .onChange(of: totalText) { _, newValue in
            let digits = newValue.filter(\.isNumber)
            if digits != newValue { totalText = digits }
        }
        .onChange(of: car) { _, newValue in
            if newValue.count > 16 { car = String(newValue.prefix(16)) }
        }
    }

    private var validTotal: Int? {
        guard let total = Int(totalText), total > 0 else { return nil }
        return total
    }

    private func generate() async {
        guard let client = model.client else { error = APIError.invalidBaseURL.localizedDescription; return }
        guard let total = validTotal else { return }
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
    @State private var userID = ""
    @State private var workflowResponse: WorkflowResponse?
    @State private var orderResponse: OrderResponse?
    @State private var isLoading = false
    @State private var error: String?
    @FocusState private var isUserIDFieldFocused: Bool

    var body: some View {
        Form {
            Section("Temporal") {
                Button("Run Hello Workflow") { Task { await runHello() } }
                HStack {
                    Button("Place Order") { Task { await placeOrder() } }
                        .disabled(userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                    ClickToEnterField(
                        prompt: "Enter user ID",
                        text: $userID,
                        isFocused: $isUserIDFieldFocused
                    )
                }
            }
            if let workflowResponse {
                Section("Result") {
                    LabeledContent("Message", value: workflowResponse.result)
                    LabeledContent("Workflow ID") {
                        if let url = model.client?.temporalWorkflowURL(workflowID: workflowResponse.workflowID) {
                            Link(workflowResponse.workflowID, destination: url)
                                .help("Open this workflow in Temporal UI")
                        } else {
                            Text(workflowResponse.workflowID).textSelection(.enabled)
                        }
                    }
                }
            }
            if let orderResponse {
                Section("Order") {
                    LabeledContent("Order ID", value: orderResponse.id)
                    LabeledContent("User ID", value: orderResponse.userID)
                    LabeledContent("Created", value: orderResponse.created)
                    LabeledContent("Workflow ID") {
                        if let url = model.client?.temporalWorkflowURL(workflowID: orderResponse.workflowID) {
                            Link(orderResponse.workflowID, destination: url)
                                .help("Open this workflow in Temporal UI")
                        } else {
                            Text(orderResponse.workflowID).textSelection(.enabled)
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

    private func runHello() async {
        guard let client = model.client else { error = APIError.invalidBaseURL.localizedDescription; return }
        isLoading = true; defer { isLoading = false }
        do {
            workflowResponse = try await client.hello()
            orderResponse = nil
            error = nil
        }
        catch { self.error = error.localizedDescription }
    }

    private func placeOrder() async {
        guard let client = model.client else { error = APIError.invalidBaseURL.localizedDescription; return }
        let trimmedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUserID.isEmpty else { return }
        isLoading = true; defer { isLoading = false }
        do {
            orderResponse = try await client.order(userID: trimmedUserID)
            workflowResponse = nil
            error = nil
        }
        catch { self.error = error.localizedDescription }
    }
}

private struct RoundedEntryField: View {
    let placeholder: String
    @Binding var text: String
    @State private var isFocused = false

    var body: some View {
        HStack(spacing: 10) {
            Text("👉")
                .font(.title3)
            NativeTextField(
                placeholder: placeholder,
                text: $text,
                isFocused: $isFocused
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
                .stroke(
                    isFocused ? Color.accentColor : Color.secondary.opacity(0.35),
                    lineWidth: 1
                )
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

private struct NativeTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var alignment: NSTextAlignment = .left

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, alignment: alignment)
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
        field.alignment = alignment
        field.baseWritingDirection = .leftToRight
        field.cell?.alignment = alignment
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder
        field.alignment = alignment
        field.baseWritingDirection = .leftToRight
        field.cell?.alignment = alignment
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        @Binding private var isFocused: Bool
        private let alignment: NSTextAlignment

        init(
            text: Binding<String>,
            isFocused: Binding<Bool>,
            alignment: NSTextAlignment
        ) {
            _text = text
            _isFocused = isFocused
            self.alignment = alignment
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isFocused = true
            if let editor = (notification.object as? NSTextField)?.currentEditor() {
                editor.alignment = alignment
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

struct QuickLinkView: View {
    @Environment(AppModel.self) private var model
    @State private var image: NSImage?
    @State private var error: String?
    @State private var isShowingBrowser = false

    var body: some View {
        Form {
            Section("Galaxy Lens") {
                Button("Open Galaxy Lens") {
                    isShowingBrowser = true
                }
            }

            Section("Server Image") {
                Button("Load Image") { Task { await load() } }
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 420)
                }
            }
            ErrorSection(message: error)
        }
        .formStyle(.grouped)
        .navigationTitle("Quick Links")
        .sheet(isPresented: $isShowingBrowser) {
            QuickLinkBrowserView(
                url: URL(string: "https://r.galaxylens.de/")!,
                isPresented: $isShowingBrowser
            )
        }
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

private struct QuickLinkBrowserView: View {
    let url: URL
    @Binding var isPresented: Bool
    @State private var webView = WKWebView()
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var currentURL = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { webView.goBack() } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)
                .help("Back")

                Button { webView.goForward() } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)
                .help("Forward")

                Button { webView.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")

                Text(currentURL.isEmpty ? url.absoluteString : currentURL)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Spacer()
                if isLoading { ProgressView().controlSize(.small) }
                Button("Close") { isPresented = false }
            }
            .padding(12)

            Divider()

            EmbeddedWebView(
                webView: webView,
                canGoBack: $canGoBack,
                canGoForward: $canGoForward,
                currentURL: $currentURL,
                isLoading: $isLoading
            )
        }
        .frame(minWidth: 900, minHeight: 650)
        .onAppear {
            if webView.url == nil {
                webView.load(URLRequest(url: url))
            }
        }
    }
}

private struct EmbeddedWebView: NSViewRepresentable {
    let webView: WKWebView
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var currentURL: String
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            canGoBack: $canGoBack,
            canGoForward: $canGoForward,
            currentURL: $currentURL,
            isLoading: $isLoading
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.update(from: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private var canGoBack: Binding<Bool>
        private var canGoForward: Binding<Bool>
        private var currentURL: Binding<String>
        private var isLoading: Binding<Bool>

        init(
            canGoBack: Binding<Bool>,
            canGoForward: Binding<Bool>,
            currentURL: Binding<String>,
            isLoading: Binding<Bool>
        ) {
            self.canGoBack = canGoBack
            self.canGoForward = canGoForward
            self.currentURL = currentURL
            self.isLoading = isLoading
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            update(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
            update(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            update(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation?,
            withError error: any Error
        ) {
            update(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: any Error
        ) {
            update(from: webView)
        }

        func update(from webView: WKWebView) {
            canGoBack.wrappedValue = webView.canGoBack
            canGoForward.wrappedValue = webView.canGoForward
            currentURL.wrappedValue = webView.url?.absoluteString ?? ""
            isLoading.wrappedValue = webView.isLoading
        }
    }
}

struct ErrorSection: View {
    let message: String?
    var body: some View {
        if let message { Section("Error") { CopyableErrorText(message: message) } }
    }
}

private struct CopyableErrorText: View {
    let message: String

    var body: some View {
        Text(message)
            .foregroundStyle(.red)
            .textSelection(.enabled)
            .contextMenu {
                Button("Copy Error") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                }
            }
    }
}
