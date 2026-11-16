import SwiftUI

struct AsphaltTasksView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingTask: AsphaltTaskType?
    @State private var showConfirmation = false
    @State private var isSending = false
    @State private var response: AsphaltTaskResponse?
    @State private var responseIsExpanded = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Task") {
                taskButton(.reset, role: .destructive)
                taskButton(.refillAds)
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
                Task { await send(task) }
            }
        } message: { task in
            Text(task.confirmationMessage)
        }
    }

    @ViewBuilder
    private func taskButton(
        _ task: AsphaltTaskType,
        role: ButtonRole? = nil
    ) -> some View {
        Button(task.title, role: role) {
            pendingTask = task
            showConfirmation = true
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(isSending)
    }

    @MainActor
    private func send(_ task: AsphaltTaskType) async {
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
            response = try await client.sendAsphaltTask(task)
            responseIsExpanded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
