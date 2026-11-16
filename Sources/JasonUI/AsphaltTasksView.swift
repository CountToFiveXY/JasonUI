import SwiftUI

struct AsphaltTasksView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingTask: AsphaltTaskType?
    @State private var showConfirmation = false
    @State private var isSending = false
    @State private var response: AsphaltTaskResponse?
    @State private var responseIsExpanded = false
    @State private var errorMessage: String?
    @State private var refillRepeat = 8
    @State private var refillRepeatDraft = ""
    @State private var isEditingRefillRepeat = false
    @State private var pendingRepeat = 8
    @FocusState private var isRefillRepeatFocused: Bool

    var body: some View {
        Form {
            Section("Task") {
                taskRow(
                    .reset,
                    annotation: "Reset AL to restore ad count to 20"
                )
                taskRow(
                    .refillAds,
                    showsRepeatInput: true
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
                    pendingRepeat = commitRefillRepeat()
                }
                pendingTask = task
                showConfirmation = true
            }
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
        if isEditingRefillRepeat {
            TextField("8", text: $refillRepeatDraft)
                .frame(width: 48)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .focused($isRefillRepeatFocused)
                .accessibilityLabel("Refill repeat count")
                .onChange(of: refillRepeatDraft) { _, value in
                    refillRepeatDraft = sanitizedRepeatDraft(value)
                }
                .onSubmit { _ = commitRefillRepeat() }
                .onChange(of: isRefillRepeatFocused) { _, focused in
                    if !focused && isEditingRefillRepeat {
                        _ = commitRefillRepeat()
                    }
                }
                .onAppear { isRefillRepeatFocused = true }
                .disabled(isSending)
        } else {
            Text(String(refillRepeat))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
                .onTapGesture {
                    refillRepeatDraft = ""
                    isEditingRefillRepeat = true
                }
                .help("Click to change the refill repeat count")
                .accessibilityLabel("Refill repeat count: \(refillRepeat). Click to edit.")
        }
    }

    private func sanitizedRepeatDraft(_ value: String) -> String {
        let digits = String(value.filter(\.isNumber).prefix(2))
        return Int(digits) == 0 ? "" : digits
    }

    @discardableResult
    private func commitRefillRepeat() -> Int {
        let value = Int(refillRepeatDraft).flatMap { (1...99).contains($0) ? $0 : nil } ?? 8
        refillRepeat = value
        refillRepeatDraft = String(value)
        isEditingRefillRepeat = false
        isRefillRepeatFocused = false
        return value
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
