import SwiftUI

struct AsphaltTasksView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingTask: AsphaltTaskType?
    @State private var showConfirmation = false
    @State private var isSending = false
    @State private var response: AsphaltTaskResponse?
    @State private var responseIsExpanded = false
    @State private var errorMessage: String?
    @State private var refillRepeat = ""
    @State private var isHoveringRefillRepeat = false
    @State private var pendingRepeat = 8
    @FocusState private var isRefillRepeatFocused: Bool

    var body: some View {
        Form {
            Section("Task") {
                taskRow(
                    .refillAds,
                    showsRepeatInput: true
                )
                taskRow(.startGame)
                taskRow(.closeGame)
                taskRow(
                    .reset,
                    annotation: "Reset AL to restore ad count to 20"
                )
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
            Button("Cancel", role: .cancel) {}
            Button("Confirm", role: task == .reset ? .destructive : nil) {
                Task { await send(task, repeatCount: pendingRepeat) }
            }
        } message: { task in
            if task == .refillAds {
                Text("This will send one refill task with a repeat count of \(pendingRepeat).")
            } else {
                Text(task.confirmationMessage)
            }
        }
    }

    @ViewBuilder
    private func taskRow(
        _ task: AsphaltTaskType,
        annotation: String? = nil,
        showsRepeatInput: Bool = false
    ) -> some View {
        HStack {
            Button(task.title) {
                if task == .refillAds {
                    pendingRepeat = refillRepeatValue
                }
                pendingTask = task
                showConfirmation = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSending)

            Spacer()

            if let annotation {
                Text(annotation)
                    .foregroundStyle(.secondary)
            }

            if showsRepeatInput {
                refillRepeatControl
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var refillRepeatControl: some View {
        ZStack(alignment: .trailing) {
            TextField("", text: $refillRepeat)
                .multilineTextAlignment(.trailing)
                .focused($isRefillRepeatFocused)
                .accessibilityLabel("Refill repeat count")
                .onChange(of: refillRepeat) { _, value in
                    refillRepeat = sanitizedRepeat(value)
                }
                .disabled(isSending)

            if refillRepeat.isEmpty && !isRefillRepeatFocused {
                Text("8")
                    .foregroundStyle(isHoveringRefillRepeat ? Color.accentColor : .secondary)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                    .onTapGesture { isRefillRepeatFocused = true }
                    .onHover { isHoveringRefillRepeat = $0 }
            }
        }
        .frame(width: 48)
        .help("Repeat count; defaults to 8")
    }

    private func sanitizedRepeat(_ value: String) -> String {
        let digits = String(value.filter(\.isNumber).prefix(2))
        return Int(digits) == 0 ? "" : digits
    }

    private var refillRepeatValue: Int {
        Int(refillRepeat).flatMap { (1...99).contains($0) ? $0 : nil } ?? 8
    }

    @MainActor
    private func send(_ task: AsphaltTaskType, repeatCount: Int) async {
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
                repeatCount: task == .refillAds ? repeatCount : nil
            )
            responseIsExpanded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
