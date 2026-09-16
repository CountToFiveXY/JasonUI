import AppKit
import SwiftUI
import WebKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Feature = .dashboard
    @State private var updateManager = AppUpdateManager()
    @AppStorage("sidebarAsphaltExpanded") private var isAsphaltExpanded = true

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    sidebarRow(.dashboard)
                    sidebarRow(.ledger)
                    sidebarRow(.shortener)
                    DisclosureGroup(isExpanded: $isAsphaltExpanded) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Feature.asphaltLegends) { sidebarRow($0, indented: true) }
                        }
                    } label: {
                        Label("Asphalt Legends", systemImage: "flag.checkered")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .padding(.vertical, 7)
                    }
                    .padding(.horizontal, 10)
                    sidebarRow(.workflows)
                    sidebarRow(.quickLink)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.vertical, 8)
                .clipped()
                Divider()
                GitHubFooter(updateManager: updateManager)
            }
            .frame(width: 228)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            NavigationStack {
                Group {
                    switch selection {
                    case .dashboard: DashboardView()
                    case .ledger: LedgerView()
                    case .shortener: URLShortenerView()
                    case .ranking: RankingView()
                    case .leaderboard: LeaderboardView()
                    case .workflows: WorkflowsView()
                    case .quickLink: QuickLinkView()
                    }
                }
                .padding(24)
            }
        }
        .task { await model.checkConnection() }
        .task { await updateManager.monitorForUpdates() }
    }

    private func sidebarRow(_ feature: Feature, indented: Bool = false) -> some View {
        Button {
            selection = feature
        } label: {
            Label(feature.title, systemImage: feature.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, indented ? 16 : 0)
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .foregroundStyle(selection == feature ? Color.white : Color.primary)
                .background(
                    selection == feature ? Color.accentColor : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
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
    case dashboard, ledger, shortener, ranking, leaderboard, workflows, quickLink
    var id: String { rawValue }

    /// The features grouped under the Asphalt Legends heading in the sidebar.
    static let asphaltLegends: [Feature] = [.ranking, .leaderboard]
    var title: String {
        switch self {
        case .dashboard: "Server"
        case .ledger: "Ledger"
        case .shortener: "URL Shortener"
        case .ranking: "Ranking Card"
        case .leaderboard: "Leaderboard"
        case .workflows: "Workflows"
        case .quickLink: "Quick Links"
        }
    }
    var icon: String {
        switch self {
        case .dashboard: "server.rack"
        case .ledger: "list.bullet.rectangle.portrait"
        case .shortener: "link"
        case .ranking: "chart.bar.doc.horizontal"
        case .leaderboard: "stopwatch"
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
                ServiceStatusRow(title: "Kafka", state: model.kafkaState)
                ServiceStatusRow(title: "Temporal", state: model.temporalState)
                ServiceStatusRow(title: "Google Cloud / Firestore", state: model.googleCloudState)
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

/// `NativeTextField` inside the same visible box as `BoxedTextField`.
///
/// The ranking fields keep the AppKit field, which pins the writing direction
/// left-to-right; only the box around it is new.
private struct BoxedNativeField: View {
    let placeholder: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var width: CGFloat
    var alignment: NSTextAlignment = .left

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 7) }

    var body: some View {
        NativeTextField(
            placeholder: placeholder,
            text: $text,
            isFocused: $isFocused,
            alignment: alignment
        )
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(width: width)
        .background(shape.fill(Color(nsColor: .textBackgroundColor)))
        .overlay(
            shape.strokeBorder(
                isFocused ? Color.accentColor : Color.secondary.opacity(0.4),
                lineWidth: isFocused ? 2 : 1
            )
        )
    }
}

struct RankingView: View {
    private static let slots = 3

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(1...Self.slots, id: \.self) { slot in
                    RankingCardSection(slot: slot)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 2)
        }
        // A two-axis scroll view centres content smaller than its viewport, so
        // the anchor is what actually pins the cards to the top-left.
        .defaultScrollAnchor(.topLeading)
        .navigationTitle("Ranking Card")
    }
}

/// One complete card generator. Several sit side by side so a set of cards can
/// be produced in one pass, each keeping its own remembered inputs.
private struct RankingCardSection: View {
    @Environment(AppModel.self) private var model

    // The event-type row sets the floor: the picker plus the percentage text
    // has to fit without wrapping, and everything else lines up to it.
    private static let cardWidth: CGFloat = 268
    private static let fieldWidth: CGFloat = 240
    private static let pickerWidth: CGFloat = 138
    private static let totalWidth: CGFloat = 142

    private let slot: Int

    // Remembered across launches, keyed per card.
    @AppStorage private var type: CardType
    @AppStorage private var car: String
    @AppStorage private var totalText: String

    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var error: String?
    @State private var didCopy = false
    @State private var isTotalFieldFocused = false
    @State private var isCarFieldFocused = false

    init(slot: Int) {
        self.slot = slot
        // Each card starts on a different event type, most-used first; changing
        // one is remembered.
        let order: [CardType] = [.ch, .sp, .se]
        let defaultType = order[(slot - 1) % order.count]
        _type = AppStorage(wrappedValue: defaultType, "rankingCardType.\(slot)")
        _car = AppStorage(wrappedValue: "", "rankingCarName.\(slot)")
        _totalText = AppStorage(wrappedValue: "", "rankingTotalParticipants.\(slot)")
    }

    var body: some View {
        GroupBox("Card \(slot)") {
            VStack(alignment: .leading, spacing: 12) {
                // Labels sit above their fields: a column this narrow has no
                // room for the side-by-side form layout.
                labeled("Event Type") {
                    HStack(spacing: 6) {
                        Picker("", selection: $type) {
                            ForEach(CardType.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: Self.pickerWidth, alignment: .leading)
                        Text(type.percentageSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .help("The percentage rows this card will show")
                    }
                    .frame(width: Self.fieldWidth, alignment: .leading)
                }
                labeled("Car Name") {
                    BoxedNativeField(
                        placeholder: "Enter Car",
                        text: $car,
                        isFocused: $isCarFieldFocused,
                        width: Self.fieldWidth
                    )
                }
                labeled("Total Participants") {
                    HStack(spacing: 8) {
                        BoxedNativeField(
                            placeholder: "Total",
                            text: $totalText,
                            isFocused: $isTotalFieldFocused,
                            width: Self.totalWidth
                        )
                        Spacer(minLength: 6)
                        Button(isLoading ? "Generating…" : "Generate") {
                            Task { await generate() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canGenerate)
                        .help("Generate the card and copy it to the clipboard")
                    }
                    .frame(width: Self.fieldWidth, alignment: .leading)
                }

                if let error {
                    CopyableErrorText(message: error)
                        .font(.caption)
                }

                if let image {
                    VStack(spacing: 6) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 228, maxHeight: 380)
                            .shadow(radius: 6)
                            // Re-copying without regenerating, which would
                            // stamp the card with a new timestamp.
                            .onTapGesture { didCopy = copyImage(image) }
                            .help("Click the card to copy it again")
                        Label(
                            didCopy ? "Copied to clipboard" : "Click the card to copy",
                            systemImage: didCopy ? "checkmark.circle.fill" : "doc.on.doc"
                        )
                        .font(.caption2)
                        .foregroundStyle(didCopy ? Color.green : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
            }
            .padding(3)
            .frame(width: Self.cardWidth, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: totalText) { _, newValue in
            let digits = newValue.filter(\.isNumber)
            if digits != newValue { totalText = digits }
        }
        .onChange(of: car) { _, newValue in
            if newValue.count > 16 { car = String(newValue.prefix(16)) }
        }
    }

    @ViewBuilder
    private func labeled(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private var canGenerate: Bool {
        validTotal != nil
            && !car.trimmingCharacters(in: .whitespaces).isEmpty
            && !isLoading
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
            // Generating copies as well: the card is always wanted on the
            // clipboard, so a second click was pure ceremony.
            didCopy = copyImage(preview)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    @discardableResult
    private func copyImage(_ image: NSImage) -> Bool {
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([image])
    }
}

struct WorkflowsView: View {
    @Environment(AppModel.self) private var model
    @State private var userID = ""
    @State private var kafkaOrderID = ""
    @State private var workflowResponse: WorkflowResponse?
    @State private var orderResponse: OrderResponse?
    @State private var kafkaResponse: KafkaMessageResponse?
    @State private var isLoading = false
    @State private var error: String?
    @FocusState private var isUserIDFieldFocused: Bool
    @FocusState private var isKafkaOrderIDFieldFocused: Bool

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
            Section("Kafka") {
                HStack {
                    Button("Send Success Message") { Task { await sendKafkaMessage() } }
                        .disabled(
                            kafkaOrderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    Spacer()
                    ClickToEnterField(
                        prompt: "Enter order ID",
                        text: $kafkaOrderID,
                        isFocused: $isKafkaOrderIDFieldFocused
                    )
                }
                LabeledContent("Status", value: "SUCCESS")
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
                    LabeledContent("Firestore") {
                        if let url = model.client?.firestoreOrderURL(orderID: orderResponse.id) {
                            Link("Open document", destination: url)
                                .help("Open this order in the Firebase console")
                        }
                    }
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
            if let kafkaResponse {
                Section("Kafka Message") {
                    LabeledContent("Order ID", value: kafkaResponse.id)
                    LabeledContent("Status", value: kafkaResponse.status)
                    LabeledContent("Topic", value: kafkaResponse.topic)
                    LabeledContent("Partition", value: String(kafkaResponse.partition))
                    LabeledContent("Offset", value: String(kafkaResponse.offset))
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
            let response = try await client.order(userID: trimmedUserID)
            orderResponse = response
            kafkaOrderID = response.id
            kafkaResponse = nil
            workflowResponse = nil
            error = nil
        }
        catch { self.error = error.localizedDescription }
    }

    private func sendKafkaMessage() async {
        guard let client = model.client else {
            error = APIError.invalidBaseURL.localizedDescription
            return
        }
        let trimmedOrderID = kafkaOrderID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOrderID.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            kafkaResponse = try await client.sendOrderSuccess(orderID: trimmedOrderID)
            error = nil
        }
        catch { self.error = error.localizedDescription }
    }
}

/// Parses the lap times typed into the leaderboard.
enum LeaderboardTime {
    /// Accepts `19.62`, `19,62`, and `19.62s`.
    static func seconds(from text: String) -> Double? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasSuffix("s") { value.removeLast() }
        value = value.replacingOccurrences(of: ",", with: ".")
        guard let seconds = Double(value), seconds > 0, seconds < 3_600 else { return nil }
        return seconds
    }

    /// The editable leaderboard cells deliberately accept one display format
    /// only, so every value occupies the same compact amount of space.
    static func fixedSeconds(from text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].count == 2,
              parts[1].count == 3,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }),
              let seconds = Double(value),
              seconds > 0 else { return nil }
        return seconds
    }

    /// Keep partial values typeable while rejecting characters that can never
    /// form `xx.xxx`. The exact-format check still controls the Save button.
    static func sanitizedFixedInput(_ text: String) -> String {
        var whole = ""
        var fraction = ""
        var sawDecimal = false
        for character in text where character.isNumber || character == "." {
            if character == "." {
                if !sawDecimal { sawDecimal = true }
            } else if sawDecimal {
                if fraction.count < 3 { fraction.append(character) }
            } else if whole.count < 2 {
                whole.append(character)
            }
        }
        return sawDecimal ? "\(whole).\(fraction)" : whole
    }
}

struct LeaderboardView: View {
    private static let minimumPageWidth = CGFloat(TrackLineupPicker.slots)
        * TrackLeaderboardCard.cardWidth
        + CGFloat(TrackLineupPicker.slots - 1) * TrackLeaderboardCard.cardSpacing

    @Environment(AppModel.self) private var model
    @State private var cars: [CarSummary] = []
    @State private var trackCatalogue: [MapTrackSummary] = []
    @State private var isLoadingLineup = false
    @State private var isLoadingCatalogue = false
    /// The chosen track identifiers, one per selector slot, remembered between
    /// launches. Stored as one string because AppStorage holds no arrays.
    @AppStorage("leaderboardLineupSlots") private var storedSlots = ""
    /// The tracks on show, chosen in the selectors or read off an image.
    @State private var lineup: [Int: MapTrackLeaderboard] = [:]
    @State private var loadingSlotValues: [Int: String] = [:]
    @State private var isLoading = false
    @State private var isAddingMap = false
    @State private var error: String?

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox("Selected Gauntlet Tracks") {
                        VStack(alignment: .leading, spacing: 10) {
                            TrackLineupPicker(
                                tracks: trackCatalogue,
                                slotValues: slots,
                                onSelect: { slot, value in
                                    setSlot(value, at: slot)
                                    Task { await loadSelectedTrack(value, into: slot) }
                                }
                            )
                            Divider()
                            TrackLineupReader(
                                isLoading: isLoadingLineup,
                                onLoad: { data in await loadLineup(from: data) }
                            )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(2)
                    }

                    HStack(alignment: .top, spacing: TrackLeaderboardCard.cardSpacing) {
                        ForEach(0..<TrackLineupPicker.slots, id: \.self) { slot in
                            if loadingSlotValues[slot] != nil {
                                ProgressView()
                                    .frame(width: TrackLeaderboardCard.cardWidth, height: 80)
                            } else if let entry = lineup[slot] {
                                TrackLeaderboardCard(
                                    title: entry.displayName,
                                    subtitle: nil,
                                    times: entry.times,
                                    cars: cars,
                                    onRecord: { car, seconds in
                                        await record(
                                            mapID: entry.mapID,
                                            trackID: entry.id,
                                            car: car,
                                            seconds: seconds
                                        )
                                    },
                                    onDelete: { car in
                                        await delete(mapID: entry.mapID, trackID: entry.id, car: car)
                                    }
                                )
                                .id("\(slot)/\(entry.slotKey)")
                            } else {
                                Color.clear.frame(width: TrackLeaderboardCard.cardWidth, height: 1)
                            }
                        }
                    }

                    if let error {
                        CopyableErrorText(message: error)
                            .font(.callout)
                    }

                    Spacer(minLength: 0)

                    GroupBox("Maps") {
                        HStack(spacing: 10) {
                            Text(catalogueSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if isLoadingCatalogue { ProgressView().controlSize(.small) }
                            Spacer()
                            if let url = model.client?.firestoreMapsURL() {
                                Link("Open in Firestore", destination: url)
                                    .help("Open the maps collection in the Firebase console")
                            }
                            Button("Reload") { Task { await loadTrackCatalogue() } }
                            Button("Add Map") { isAddingMap = true }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(2)
                    }
                }
                .frame(
                    width: max(geometry.size.width, Self.minimumPageWidth),
                    height: geometry.size.height,
                    alignment: .topLeading
                )
            }
            .scrollIndicators(.visible, axes: .horizontal)
            .defaultScrollAnchor(.topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Leaderboard")
        .task { await loadCars() }
        .task { await loadTrackCatalogue() }
        .sheet(isPresented: $isAddingMap) {
            AddMapSheet(isPresented: $isAddingMap) { name, firstTrack, secondTrack in
                await create(name: name, tracks: [firstTrack, secondTrack])
            }
        }
    }

    private var catalogueSummary: String {
        guard !trackCatalogue.isEmpty else {
            return isLoadingCatalogue ? "Loading maps…" : "No maps yet. Add one to start recording times."
        }
        let maps = Set(trackCatalogue.map(\.mapID)).count
        return "\(maps) map\(maps == 1 ? "" : "s") · \(trackCatalogue.count) tracks"
    }

    private func loadTrackCatalogue() async {
        guard let client = model.client else {
            error = APIError.invalidBaseURL.localizedDescription
            return
        }
        isLoadingCatalogue = true
        defer { isLoadingCatalogue = false }
        do {
            trackCatalogue = try await client.tracks()
            migrateStoredSlotsIfNeeded()
            await loadSelectedTracks()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// A new map brings two new tracks, so the selectors are refreshed.
    private func create(name: String, tracks: [String]) async -> String? {
        guard let client = model.client else { return APIError.invalidBaseURL.localizedDescription }
        do {
            _ = try await client.createMap(name: name, tracks: tracks)
            await loadTrackCatalogue()
            error = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: line-up selection

    private var slots: [String] {
        let parts = storedSlots
            .split(separator: "\u{1}", omittingEmptySubsequences: false)
            .map(String.init)
        return (0..<TrackLineupPicker.slots).map { $0 < parts.count ? parts[$0] : "" }
    }

    private func setSlot(_ value: String, at index: Int) {
        var parts = slots
        parts[index] = value
        storedSlots = parts.joined(separator: "\u{1}")
        if value.isEmpty {
            lineup[index] = nil
            loadingSlotValues[index] = nil
        }
    }

    /// Older builds stored only a track id. Convert those values to the
    /// map-qualified keys used by the grouped menu whenever the match is clear.
    private func migrateStoredSlotsIfNeeded() {
        var parts = slots
        var changed = false
        for index in parts.indices where !parts[index].isEmpty && !parts[index].contains("/") {
            let matches = trackCatalogue.filter { $0.id == parts[index] }
            if matches.count == 1, let match = matches.first {
                parts[index] = match.slotKey
                changed = true
            }
        }
        if changed {
            storedSlots = parts.joined(separator: "\u{1}")
        }
    }

    private func loadSelectedTracks() async {
        for (slot, value) in slots.enumerated() where !value.isEmpty {
            await loadSelectedTrack(value, into: slot)
        }
    }

    private func loadSelectedTrack(_ value: String, into slot: Int) async {
        guard !value.isEmpty else {
            lineup[slot] = nil
            return
        }
        guard let summary = trackCatalogue.first(where: { $0.slotKey == value }) else {
            lineup[slot] = nil
            return
        }
        guard let client = model.client else {
            error = APIError.invalidBaseURL.localizedDescription
            return
        }

        loadingSlotValues[slot] = value
        defer {
            if loadingSlotValues[slot] == value {
                loadingSlotValues[slot] = nil
            }
        }
        do {
            let map = try await client.mapLeaderboard(mapID: summary.mapID)
            guard slots[slot] == value else { return }
            guard let track = map.tracks.first(where: { $0.id == summary.id }) else {
                error = "Track '\(summary.displayName)' was not found in \(summary.mapName)."
                lineup[slot] = nil
                return
            }
            lineup[slot] = MapTrackLeaderboard(
                id: track.id,
                name: track.name,
                chineseName: track.chineseName,
                times: track.times,
                mapID: summary.mapID,
                mapName: summary.mapName,
                mapChineseName: summary.mapChineseName,
                requestedName: summary.name
            )
            error = nil
        } catch {
            guard slots[slot] == value else { return }
            self.error = error.localizedDescription
        }
    }

    /// Read a line-up from an image. Dropdown changes load their own table
    /// immediately, so this explicit action belongs only to image input.
    private func loadLineup(from image: Data?) async -> String? {
        guard let client = model.client else {
            error = APIError.invalidBaseURL.localizedDescription
            return nil
        }
        isLoadingLineup = true
        defer { isLoadingLineup = false }

        do {
            guard let image else { return "Paste or drop an image first." }
            let names = try await client.readText(image: image).lines.map(\.text)
            guard !names.isEmpty else {
                error = nil
                return "No text was found in that image."
            }

            let lookup = try await client.lookupTracks(names: names)
            lineup = Dictionary(
                uniqueKeysWithValues: lookup.tracks.prefix(TrackLineupPicker.slots)
                    .enumerated().map { ($0.offset, $0.element) }
            )
            error = nil

            var parts = Array(repeating: "", count: TrackLineupPicker.slots)
            for (index, track) in lookup.tracks.prefix(parts.count).enumerated() {
                parts[index] = track.slotKey
            }
            storedSlots = parts.joined(separator: "\u{1}")

            var status = "Loaded \(lookup.tracks.count) of \(names.count)."
            if !lookup.unmatched.isEmpty {
                status += " No match: " + lookup.unmatched.joined(separator: ", ")
            }
            return status
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    private func loadCars() async {
        guard let client = model.client else { return }
        cars = (try? await client.cars()) ?? cars
    }

    private func record(
        mapID: String,
        trackID: String,
        car: String,
        seconds: Double
    ) async -> Bool {
        let saved = await update(mapID: mapID) { client in
            try await client.recordLapTime(
                mapID: mapID,
                trackID: trackID,
                car: car,
                seconds: seconds
            )
        }
        let isNewCar = !cars.contains { $0.name.caseInsensitiveCompare(car) == .orderedSame }
        if saved && isNewCar {
            await loadCars()
        }
        return saved
    }

    private func delete(mapID: String, trackID: String, car: String) async -> Bool {
        await update(mapID: mapID) { client in
            try await client.deleteLapTime(mapID: mapID, trackID: trackID, car: car)
        }
    }

    /// Runs a track mutation and swaps the refreshed track into whichever
    /// list is on screen — the selected map's, the line-up's, or both.
    private func update(
        mapID: String,
        _ mutation: (APIClient) async throws -> TrackLeaderboard
    ) async -> Bool {
        guard let client = model.client else {
            error = APIError.invalidBaseURL.localizedDescription
            return false
        }
        do {
            let track = try await mutation(client)
            lineup = lineup.mapValues { entry in
                entry.mapID == mapID && entry.id == track.id
                    ? entry.replacingTimes(track.times)
                    : entry
            }
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
}

/// A text field with a filled background and border, so it reads as something
/// you can click. Plain `TextField`s render borderless inside a grouped `Form`.
private struct BoxedTextField: View {
    let placeholder: String
    @Binding var text: String
    var width: CGFloat? = nil
    var alignment: TextAlignment = .leading
    @FocusState private var isFocused: Bool

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 7) }

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder))
            .textFieldStyle(.plain)
            .labelsHidden()
            .multilineTextAlignment(alignment)
            .focused($isFocused)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(width: width)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(shape.fill(Color(nsColor: .textBackgroundColor)))
            .overlay(
                shape.strokeBorder(
                    isFocused ? Color.accentColor : Color.secondary.opacity(0.4),
                    lineWidth: isFocused ? 2 : 1
                )
            )
            .contentShape(shape)
            .onTapGesture { isFocused = true }
    }
}

/// What the car selector in the input row is currently set to.
private enum CarChoice: Hashable {
    case unselected
    case existing(String)
    case other
}

/// One track's leaderboard, narrow enough that several sit side by side.
private struct TrackLeaderboardCard: View {
    let title: String
    /// Shown under the title when the card's map is not otherwise obvious,
    /// which it is not for a line-up spanning several maps.
    let subtitle: String?
    let times: [LapTimeEntry]
    let cars: [CarSummary]
    let onRecord: (String, Double) async -> Bool
    let onDelete: (String) async -> Bool

    @State private var carChoice = CarChoice.unselected
    @State private var car = ""
    @State private var timeText = ""
    @State private var timeDrafts: [String: String] = [:]
    @State private var isSaving = false

    // Wide enough for an editable time and explicit Save action. The entire
    // Leaderboard page scrolls horizontally when five cards exceed the window.
    static let cardWidth: CGFloat = 218
    static let cardSpacing: CGFloat = 10
    static let carWidth: CGFloat = 74
    static let timeWidth: CGFloat = 68
    static let saveWidth: CGFloat = 46
    private static let deleteWidth: CGFloat = 18

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                if times.isEmpty {
                    Text("No times yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 7)
                } else {
                    ForEach(times) { entry in
                        EditableLapTimeRow(
                            entry: entry,
                            timeText: timeBinding(for: entry),
                            onDelete: { await delete(entry.car) }
                        )
                        Divider()
                    }
                }
                inputs
            }
            .frame(width: Self.cardWidth, alignment: .leading)
            .padding(.horizontal, 2)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .help([title, subtitle].compactMap { $0 }.joined(separator: " — "))
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("Car").frame(width: Self.carWidth, alignment: .leading)
            Text("Time(s)").frame(width: Self.timeWidth, alignment: .trailing)
            Spacer(minLength: 0)
            Spacer().frame(width: Self.deleteWidth)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 4)
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Picker("", selection: $carChoice) {
                    Text("Select car").tag(CarChoice.unselected)
                    if !cars.isEmpty {
                        Divider()
                        ForEach(cars) { car in
                            Text(car.name).tag(CarChoice.existing(car.name))
                        }
                    }
                    Divider()
                    Text("Other…").tag(CarChoice.other)
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 94)
                BoxedTextField(
                    placeholder: "18.520",
                    text: $timeText,
                    width: Self.timeWidth,
                    alignment: .trailing
                )
                Button(isSaving ? "…" : "Save") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(width: Self.saveWidth)
                .disabled(!canSave || isSaving)
            }
            if carChoice == .other {
                BoxedTextField(placeholder: "New car", text: $car)
            }
        }
        .padding(.top, 7)
        .onChange(of: carChoice) { _, choice in
            switch choice {
            case .unselected:
                timeText = ""
            case let .existing(name):
                timeText = timeDrafts[name]
                    ?? times.first(where: { $0.car == name })?.displayTime
                    ?? ""
            case .other:
                timeText = ""
            }
        }
        .onChange(of: timeText) { _, value in
            let sanitized = LeaderboardTime.sanitizedFixedInput(value)
            if sanitized != value {
                timeText = sanitized
                return
            }
            if case let .existing(name) = carChoice,
               times.contains(where: { $0.car == name }) {
                timeDrafts[name] = sanitized
            }
        }
    }

    /// The car the input row will save: a pick from the list, or a typed name.
    private var chosenCar: String {
        switch carChoice {
        case .unselected: ""
        case let .existing(name): name
        case .other: car.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var canSave: Bool {
        !chosenCar.isEmpty && LeaderboardTime.fixedSeconds(from: timeText) != nil
    }

    private func save() async {
        guard let seconds = LeaderboardTime.fixedSeconds(from: timeText), !chosenCar.isEmpty else {
            return
        }
        isSaving = true
        defer { isSaving = false }
        if await onRecord(chosenCar, seconds) {
            timeDrafts[chosenCar] = nil
            carChoice = .unselected
            car = ""
            timeText = ""
        }
    }

    private func timeBinding(for entry: LapTimeEntry) -> Binding<String> {
        Binding(
            get: { timeDrafts[entry.car] ?? entry.displayTime },
            set: { value in
                let sanitized = LeaderboardTime.sanitizedFixedInput(value)
                timeDrafts[entry.car] = sanitized
                carChoice = .existing(entry.car)
                timeText = sanitized
            }
        )
    }

    private func delete(_ car: String) async -> Bool {
        let deleted = await onDelete(car)
        if deleted {
            timeDrafts[car] = nil
            if chosenCar == car {
                carChoice = .unselected
                timeText = ""
            }
        }
        return deleted
    }
}

/// An existing result remains readable like a table row, but its time can be
/// corrected in place. Saving uses the same idempotent PUT as adding a time.
private struct EditableLapTimeRow: View {
    let entry: LapTimeEntry
    @Binding var timeText: String
    let onDelete: () async -> Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(entry.car)
                .fontWeight(entry.rank == 1 ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(entry.car)
                .frame(width: TrackLeaderboardCard.carWidth, alignment: .leading)
            TextField("Time", text: $timeText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .multilineTextAlignment(.trailing)
                .font(.system(.callout, design: .monospaced))
                .frame(width: TrackLeaderboardCard.timeWidth)
            Spacer(minLength: 0)
            Button {
                Task { _ = await onDelete() }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove \(entry.car) from this track")
            .frame(width: 18)
        }
        .font(.callout)
        .padding(.vertical, 3)
    }
}

/// Picks the tracks to show, as a row of selectors. The chosen identifiers
/// live in the pane so an image can fill them in.
private struct TrackLineupPicker: View {
    static let slots = 5

    let tracks: [MapTrackSummary]
    let slotValues: [String]
    let onSelect: (Int, String) -> Void

    private struct MapGroup: Identifiable {
        let id: String
        let name: String
        var tracks: [MapTrackSummary]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: TrackLeaderboardCard.cardSpacing) {
                ForEach(0..<Self.slots, id: \.self) { slot in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Track \(slot + 1)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("", selection: binding(for: slot)) {
                            Text("None").tag("")
                            if !tracks.isEmpty {
                                Divider()
                                ForEach(groups) { group in
                                    Section(group.name) {
                                        ForEach(group.tracks) { track in
                                            Text(track.displayName).tag(track.slotKey)
                                        }
                                    }
                                }
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: TrackLeaderboardCard.cardWidth)
                    }
                }
            }

            Text(chosenCount == 0
                 ? "Pick up to five tracks, or read them from an image below."
                 : "\(chosenCount) track\(chosenCount == 1 ? "" : "s") selected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chosenCount: Int {
        slotValues.filter { !$0.isEmpty }.count
    }

    /// Preserve the backend's map release order and each map's track order.
    private var groups: [MapGroup] {
        tracks.reduce(into: []) { groups, track in
            if let index = groups.firstIndex(where: { $0.id == track.mapID }) {
                groups[index].tracks.append(track)
            } else {
                groups.append(MapGroup(id: track.mapID, name: track.mapName, tracks: [track]))
            }
        }
    }

    private func binding(for slot: Int) -> Binding<String> {
        Binding(
            get: { slot < slotValues.count ? slotValues[slot] : "" },
            set: { onSelect(slot, $0) }
        )
    }
}

/// The image alternative, and the one button that loads the line-up: from the
/// pasted image when there is one, otherwise from the selectors above.
private struct TrackLineupReader: View {
    let isLoading: Bool
    let onLoad: (Data?) async -> String?

    @State private var image: NSImage?
    @State private var status: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("or from an image")
                .font(.caption)
                .foregroundStyle(.secondary)
            dropTarget
            Button("Paste Image") { pasteFromClipboard() }
            Button(isLoading ? "Loading…" : "Load Times") {
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading || image == nil)
            .help("Read the track names from the image, then load their times")
            // Only an image can be cleared here; the selectors keep whatever
            // the image filled in, so a line-up survives clearing the picture.
            if image != nil {
                Button("Clear") {
                    image = nil
                    status = nil
                }
                .help("Remove the image")
            }
            if let status {
                Text(status)
                    .font(.caption)
                    .textSelection(.enabled)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var dropTarget: some View {
        RoundedRectangle(cornerRadius: 7)
            .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
            .frame(width: 86, height: 34)
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().padding(2)
                } else {
                    Image(systemName: "photo.on.rectangle.angled")
                        .foregroundStyle(.secondary)
                }
            }
            .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                loadDropped(providers)
                return true
            }
            .onTapGesture { pasteFromClipboard() }
            .help("Paste or drop an image here")
    }

    private func pasteFromClipboard() {
        guard let pasted = NSImage(pasteboard: .general) else { return }
        image = pasted
        status = nil
    }

    private func loadDropped(_ providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
            // NSImage is not Sendable, so the bytes cross to the main actor
            // rather than the image itself.
            guard let dropped = object as? NSImage,
                  let encoded = Self.pngData(from: dropped) else { return }
            Task { @MainActor in
                image = NSImage(data: encoded)
                status = nil
            }
        }
    }

    private func load() async {
        let data = image.flatMap(Self.pngData)
        status = await onLoad(data)
    }

    /// NSImage carries whatever representation it was created from, so it is
    /// re-encoded as PNG for a predictable request body.
    nonisolated static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

private struct AddMapSheet: View {
    @Binding var isPresented: Bool
    let onCreate: (String, String, String) async -> String?

    @State private var name = ""
    @State private var firstTrack = ""
    @State private var secondTrack = ""
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Map")
                .font(.title3.weight(.semibold))
            Text("Both tracks are required — a map with no tracks would not appear in the track selectors. Maps and tracks cannot be renamed or removed later.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Form {
                LabeledContent("Map name") {
                    BoxedTextField(placeholder: "New York", text: $name, width: 250)
                }
                LabeledContent("First track") {
                    BoxedTextField(placeholder: "Railroad Bustle", text: $firstTrack, width: 250)
                }
                LabeledContent("Second track") {
                    BoxedTextField(placeholder: "The Tunnel", text: $secondTrack, width: 250)
                }
            }
            .formStyle(.grouped)
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button(isSaving ? "Adding…" : "Add Map") {
                    Task { await create() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate || isSaving)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var canCreate: Bool {
        let tracks = [firstTrack, secondTrack].map(Self.trimmed)
        return !Self.trimmed(name).isEmpty
            && tracks.allSatisfy { !$0.isEmpty }
            && tracks[0].caseInsensitiveCompare(tracks[1]) != .orderedSame
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        error = await onCreate(
            Self.trimmed(name),
            Self.trimmed(firstTrack),
            Self.trimmed(secondTrack)
        )
        if error == nil { isPresented = false }
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let data = try await client.image()
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
