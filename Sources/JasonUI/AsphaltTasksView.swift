import AppKit
import SwiftUI

struct AsphaltTasksView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingTask: AsphaltTaskType?
    @State private var showConfirmation = false
    @State private var showRefillConfirmation = false
    @State private var isSending = false
    @State private var response: AsphaltTaskResponse?
    @State private var responseIsExpanded = false
    @State private var errorMessage: String?
    private struct Tracking {
        let id: UUID
        let client: APIClient
    }

    @State private var tracking: [AsphaltTaskType: Tracking] = [:]
    @State private var statusText: [AsphaltTaskType: String] = [:]
    @State private var history: [AsphaltTaskHistoryEntry] = []
    @State private var historyRevision = 0
    @State private var historyError: String?
    @State private var refillRepeat = ""
    @State private var confirmationSecondsRemaining = 3
    @State private var confirmationSequence = 0
    @FocusState private var isRefillRepeatFocused: Bool

    var body: some View {
        Form {
            Section("Task") {
                HStack {
                    taskButton(.refillAds)
                    taskButton(.startGame)
                }
                HStack {
                    taskButton(.window)
                    taskButton(.closeGame)
                }
                HStack {
                    taskButton(.mute)
                    taskButton(.reset)
                }
                if isSending {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Sending…")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach([AsphaltTaskType.refillAds, .startGame, .window]) { task in
                    if let status = statusText[task] {
                        LabeledContent(task.title, value: status)
                    }
                }
            }

            if let response {
                Section {
                    DisclosureGroup("Response detail", isExpanded: $responseIsExpanded) {
                        LabeledContent("Type", value: response.type.rawValue)
                        LabeledContent("Topic") {
                            Text(response.topic)
                                .textSelection(.enabled)
                        }
                        LabeledContent("Message ID") {
                            Text(response.messageID)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            ErrorSection(message: errorMessage)
            Section("Task History · Last 10") {
                if !history.isEmpty {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                        GridRow {
                            Text("Task")
                            Text("Requested")
                            Text("Status")
                        }
                        .font(.headline)

                        ForEach(history) { entry in
                            GridRow {
                                Text(entry.repeatCount.map { "\(entry.type.title) × \($0)" } ?? entry.type.title)
                                Text(historyDate(entry.requestedAt))
                                Text(historyStatus(entry.status))
                            }
                        }
                    }
                } else if historyError == nil {
                    Text("No recent tasks").foregroundStyle(.secondary)
                }
                if let historyError {
                    Text(historyError).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Task")
        .alert(
            pendingTask.map { "Confirm \($0.title)?" } ?? "Confirm task?",
            isPresented: $showConfirmation,
            presenting: pendingTask
        ) { task in
            Button("No", role: .cancel) {
                cancelConfirmation()
            }
            Button("Yes", role: task == .reset ? .destructive : nil) {
                confirm(task)
            }
        } message: { task in
            Text(task.confirmationMessage + " " + confirmationCountdown)
        }
        .sheet(isPresented: $showRefillConfirmation) {
            refillConfirmation
        }
        .task(id: confirmationSequence) {
            await autoConfirmPendingTask()
        }
        .task(id: historyRevision) {
            await refreshHistory()
        }
    }

    private func taskButton(_ task: AsphaltTaskType) -> some View {
        Button {
            switch task {
            case .refillAds, .reset:
                pendingTask = task
                confirmationSecondsRemaining = 3
                if task == .refillAds {
                    refillRepeat = ""
                    showRefillConfirmation = true
                } else {
                    showConfirmation = true
                }
                confirmationSequence += 1
            case .startGame, .closeGame, .window, .mute:
                Task { await send(task) }
            }
        } label: {
            Text(task.title)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isSending || tracking[task] != nil)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: tracking[task]?.id) {
            await trackTask(task)
        }
    }

    private var refillConfirmation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Confirm Refill?")
                .font(.headline)
            HStack {
                Text("Count (1–99, blank uses 8)")
                TextField("", text: $refillRepeat)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .focused($isRefillRepeatFocused)
                    .accessibilityLabel("Refill count")
                    .onChange(of: refillRepeat) { previous, current in
                        if !current.isEmpty, validRefillCount(current) == nil {
                            refillRepeat = previous
                        }
                    }
            }
            Text(confirmationCountdown)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("No", role: .cancel) { cancelConfirmation() }
                    .keyboardShortcut(.cancelAction)
                Button("Yes") { confirm(.refillAds) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .defaultFocus($isRefillRepeatFocused, true)
    }

    private var confirmationCountdown: String {
        "Automatically selecting Yes in \(confirmationSecondsRemaining) seconds."
    }

    private func validRefillCount(_ text: String) -> Int? {
        guard let count = Int(text), (1...99).contains(count), String(count) == text else {
            return nil
        }
        return count
    }

    @MainActor
    private func autoConfirmPendingTask() async {
        guard let task = pendingTask else { return }
        let sequence = confirmationSequence

        for seconds in stride(from: 3, through: 1, by: -1) {
            confirmationSecondsRemaining = seconds
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard !Task.isCancelled, confirmationSequence == sequence,
                  pendingTask == task, showConfirmation || showRefillConfirmation else { return }
        }

        confirm(task)
    }

    @MainActor
    private func cancelConfirmation() {
        showConfirmation = false
        showRefillConfirmation = false
        pendingTask = nil
    }

    @MainActor
    private func confirm(_ task: AsphaltTaskType) {
        guard pendingTask == task else { return }
        let repeatCount = task == .refillAds ? validRefillCount(refillRepeat) ?? 8 : nil
        cancelConfirmation()
        Task { await send(task, repeatCount: repeatCount) }
    }

    @MainActor
    private func refreshHistory() async {
        while !Task.isCancelled {
            if let client = model.client {
                do {
                    let entries = try await client.asphaltTaskHistory()
                    guard !Task.isCancelled else { return }
                    history = entries
                    historyError = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    historyError = "Task history is temporarily unavailable."
                }
            }
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
        }
    }

    private func historyDate(_ value: String) -> String {
        let date = (try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(value, strategy: .iso8601))
        return date?.formatted(date: .abbreviated, time: .shortened) ?? value
    }

    private func historyStatus(_ status: RefillTaskResult.Status) -> String {
        switch status {
        case .queued: "Queued"
        case .submitted: "Submitted"
        case .running: "Running"
        case .succeeded: "Completed"
        case .failed: "Failed"
        case .unknown: "Outcome unknown"
        }
    }

    @MainActor
    private func trackTask(_ task: AsphaltTaskType) async {
        guard let job = tracking[task] else { return }
        let deadline = ContinuousClock.now.advanced(by: .seconds(900))
        while ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: .seconds(2))
                let result = try await job.client.refillStatus(taskID: job.id)
                guard !Task.isCancelled, tracking[task]?.id == job.id else { return }
                statusText[task] = switch result.status {
                case .queued: "Queued"
                case .submitted: "Submitted"
                case .running: task == .refillAds ? "Refilling…" : "Running…"
                case .succeeded: "Completed"
                case .failed: result.error ?? "Failed"
                case .unknown: result.error ?? "Outcome unknown"
                }
                if !result.status.isPending {
                    tracking[task] = nil
                    historyRevision += 1
                    if result.status == .succeeded {
                        NSSound(named: "Glass")?.play()
                    }
                    return
                }
            } catch {
                guard !Task.isCancelled, tracking[task]?.id == job.id else { return }
                statusText[task] = "Status temporarily unavailable; checking again…"
            }
        }
        guard !Task.isCancelled, tracking[task]?.id == job.id else { return }
        statusText[task] = "No final result received"
        tracking[task] = nil
    }

    @MainActor
    private func send(_ task: AsphaltTaskType, repeatCount: Int? = nil) async {
        guard let client = model.client else {
            errorMessage = APIError.invalidBaseURL.localizedDescription
            return
        }

        isSending = true
        response = nil
        responseIsExpanded = false
        errorMessage = nil
        defer {
            isSending = false
            historyRevision += 1
        }

        do {
            let submitted = try await client.sendAsphaltTask(
                task,
                repeatCount: repeatCount
            )
            response = submitted
            if let taskID = submitted.taskID {
                statusText[task] = "Queued"
                tracking[task] = Tracking(id: taskID, client: client)
            }
            responseIsExpanded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
