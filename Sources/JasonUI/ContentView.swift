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
                case .leaderboard: LeaderboardView()
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
    case dashboard, shortener, ranking, leaderboard, workflows, quickLink
    var id: String { rawValue }
    var title: String {
        switch self {
        case .dashboard: "Server"
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
}

struct LeaderboardView: View {
    @Environment(AppModel.self) private var model
    @State private var maps: [MapSummary] = []
    @State private var cars: [CarSummary] = []
    @State private var selectedMapID: String?
    @State private var leaderboard: MapLeaderboard?
    @State private var isLoading = false
    @State private var isAddingMap = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Map") {
                if maps.isEmpty {
                    Text(isLoading ? "Loading maps…" : "No maps yet. Add one to start recording times.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Map", selection: $selectedMapID) {
                        ForEach(maps) { map in
                            Text(map.name).tag(Optional(map.id))
                        }
                    }
                }
                HStack(spacing: 10) {
                    if isLoading && !maps.isEmpty { ProgressView().controlSize(.small) }
                    Spacer()
                    if let mapID = selectedMapID,
                       let url = model.client?.firestoreMapURL(mapID: mapID) {
                        Link("Open in Firestore", destination: url)
                            .help("Open this map in the Firebase console")
                    }
                    Button("Reload") { Task { await loadMaps() } }
                    Button("Add Map") { isAddingMap = true }
                }
            }

            if let leaderboard {
                ForEach(leaderboard.tracks) { track in
                    TrackLeaderboardSection(
                        track: track,
                        cars: cars,
                        onRecord: { car, seconds in
                            await record(trackID: track.id, car: car, seconds: seconds)
                        },
                        onDelete: { car in
                            await delete(trackID: track.id, car: car)
                        }
                    )
                    .id("\(leaderboard.id)/\(track.id)")
                }
            }

            ErrorSection(message: error)
        }
        .formStyle(.grouped)
        // A leaderboard reads as a document: let it fill a narrow window, but
        // stop it stretching across a very wide one.
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity, alignment: .top)
        .navigationTitle("Leaderboard")
        .task { await loadMaps() }
        .task { await loadCars() }
        .onChange(of: selectedMapID) { _, _ in
            Task { await loadLeaderboard() }
        }
        .sheet(isPresented: $isAddingMap) {
            AddMapSheet(isPresented: $isAddingMap) { name, firstTrack, secondTrack in
                await create(name: name, tracks: [firstTrack, secondTrack])
            }
        }
    }

    private func loadMaps() async {
        guard let client = model.client else {
            error = APIError.invalidBaseURL.localizedDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            maps = try await client.maps()
            error = nil
            if let selectedMapID, maps.contains(where: { $0.id == selectedMapID }) {
                await loadLeaderboard()
            } else {
                selectedMapID = maps.first?.id
            }
        } catch { self.error = error.localizedDescription }
    }

    private func loadCars() async {
        guard let client = model.client else { return }
        cars = (try? await client.cars()) ?? cars
    }

    private func loadLeaderboard() async {
        guard let mapID = selectedMapID else {
            leaderboard = nil
            return
        }
        guard let client = model.client else {
            error = APIError.invalidBaseURL.localizedDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            leaderboard = try await client.mapLeaderboard(mapID: mapID)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func create(name: String, tracks: [String]) async -> String? {
        guard let client = model.client else { return APIError.invalidBaseURL.localizedDescription }
        do {
            let created = try await client.createMap(name: name, tracks: tracks)
            maps = try await client.maps()
            leaderboard = created
            selectedMapID = created.id
            error = nil
            return nil
        } catch { return error.localizedDescription }
    }

    private func record(trackID: String, car: String, seconds: Double) async -> Bool {
        let saved = await update { client, mapID in
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

    private func delete(trackID: String, car: String) async -> Bool {
        await update { client, mapID in
            try await client.deleteLapTime(mapID: mapID, trackID: trackID, car: car)
        }
    }

    /// Runs a track mutation and swaps the refreshed track into the leaderboard.
    private func update(
        _ mutation: (APIClient, String) async throws -> TrackLeaderboard
    ) async -> Bool {
        guard let client = model.client, let mapID = selectedMapID else {
            error = APIError.invalidBaseURL.localizedDescription
            return false
        }
        do {
            let track = try await mutation(client, mapID)
            if let current = leaderboard {
                leaderboard = MapLeaderboard(
                    id: current.id,
                    name: current.name,
                    tracks: current.tracks.map { $0.id == track.id ? track : $0 }
                )
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

private struct TrackLeaderboardSection: View {
    let track: TrackLeaderboard
    let cars: [CarSummary]
    let onRecord: (String, Double) async -> Bool
    let onDelete: (String) async -> Bool

    @State private var carChoice = CarChoice.unselected
    @State private var car = ""
    @State private var timeText = ""
    @State private var isSaving = false

    private static let timeColumnWidth: CGFloat = 112

    var body: some View {
        Section(track.name) {
            Grid(horizontalSpacing: 14, verticalSpacing: 0) {
                GridRow {
                    Text("Car")
                        .gridColumnAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Time")
                        .gridColumnAlignment(.trailing)
                        .frame(width: Self.timeColumnWidth, alignment: .trailing)
                    Text("")
                        .gridColumnAlignment(.trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

                Divider().gridCellUnsizedAxes(.horizontal)

                if track.times.isEmpty {
                    Text("No times recorded yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 9)
                    Divider().gridCellUnsizedAxes(.horizontal)
                } else {
                    ForEach(track.times) { entry in
                        GridRow {
                            Text(entry.car)
                                .fontWeight(entry.rank == 1 ? .semibold : .regular)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(entry.displayTime)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(entry.rank == 1 ? .semibold : .regular)
                                .textSelection(.enabled)
                                .frame(width: Self.timeColumnWidth, alignment: .trailing)
                            Button {
                                Task { _ = await onDelete(entry.car) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove \(entry.car) from this track")
                        }
                        .padding(.vertical, 7)

                        Divider().gridCellUnsizedAxes(.horizontal)
                    }
                }

                GridRow {
                    VStack(alignment: .leading, spacing: 6) {
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
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if carChoice == .other {
                            BoxedTextField(placeholder: "New car", text: $car, width: 200)
                        }
                    }
                    BoxedTextField(
                        placeholder: "18.520",
                        text: $timeText,
                        width: Self.timeColumnWidth,
                        alignment: .trailing
                    )
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave || isSaving)
                }
                .padding(.top, 9)
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
        !chosenCar.isEmpty && LeaderboardTime.seconds(from: timeText) != nil
    }

    private func save() async {
        guard let seconds = LeaderboardTime.seconds(from: timeText), !chosenCar.isEmpty else {
            return
        }
        isSaving = true
        defer { isSaving = false }
        if await onRecord(chosenCar, seconds) {
            carChoice = .unselected
            car = ""
            timeText = ""
        }
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
            Text("Every map has exactly two tracks. Maps and tracks cannot be renamed or removed later.")
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
