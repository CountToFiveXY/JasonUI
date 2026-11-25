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
    @State private var refillRepeat = ""
    @State private var confirmationSecondsRemaining = 3
    @State private var confirmationSequence = 0
    @FocusState private var isRefillRepeatFocused: Bool

    var body: some View {
        Form {
            Section("Task") {
                taskRow(.refillAds)
                taskRow(.startGame)
                taskRow(.closeGame)
                taskRow(
                    .reset,
                    annotation: "Reset AL to restore ad count to 20"
                )
                taskRow(.window)
                taskRow(.mute, requiresConfirmation: false)
                if isSending {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Sending…")
                            .foregroundStyle(.secondary)
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
    }

    @ViewBuilder
    private func taskRow(
        _ task: AsphaltTaskType,
        annotation: String? = nil,
        requiresConfirmation: Bool = true
    ) -> some View {
        HStack {
            Button(task.title) {
                if requiresConfirmation {
                    pendingTask = task
                    confirmationSecondsRemaining = 3
                    if task == .refillAds {
                        refillRepeat = ""
                        showRefillConfirmation = true
                    } else {
                        showConfirmation = true
                    }
                    confirmationSequence += 1
                } else {
                    Task { await send(task) }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSending)

            Spacer()

            if let annotation {
                Text(annotation)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    private func send(_ task: AsphaltTaskType, repeatCount: Int? = nil) async {
        guard let client = model.client else {
            errorMessage = APIError.invalidBaseURL.localizedDescription
            return
        }

        isSending = true
        response = nil
        responseIsExpanded = false
        errorMessage = nil
        defer { isSending = false }

        do {
            response = try await client.sendAsphaltTask(
                task,
                repeatCount: repeatCount
            )
            responseIsExpanded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
