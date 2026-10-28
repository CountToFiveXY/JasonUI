import AppKit
import SwiftUI

struct LedgerView: View {
    @Environment(AppModel.self) private var model
    @State private var store = LedgerStore()
    @State private var purpose = ""
    @State private var amount = ""
    @State private var showClearConfirmation = false
    @State private var imageError: String?
    @State private var didCopyImage = false
    @FocusState private var focusedField: Field?

    private enum Field { case purpose, amount }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    if store.isBusy { ProgressView().controlSize(.small) }
                    if let error = store.errorMessage {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                    }
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await store.load(using: model.client) }
                    }
                    .disabled(store.isBusy)
                }
                overview
                entryCard
                recordsCard
            }
            .frame(maxWidth: 900, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("Expense Ledger")
        .task { await store.load(using: model.client) }
        .onChange(of: store.records) { _, _ in didCopyImage = false }
        .alert("Clear every expense?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                Task { if await store.clear() { didCopyImage = false } }
            }
        } message: {
            Text("This permanently removes the \(store.records.count) displayed records from Firestore on all devices.")
        }
        .alert("Could not create image", isPresented: imageErrorIsPresented) {
            Button("OK") { imageError = nil }
        } message: {
            Text(imageError ?? "Unknown error")
        }
    }

    private var overview: some View {
        HStack(spacing: 14) {
            summaryTile(
                title: "TOTAL SPENT",
                value: formattedAmount(store.totalInCents),
                icon: "creditcard.fill",
                tint: .indigo
            )
            summaryTile(
                title: "EXPENSES",
                value: store.records.count.formatted(),
                icon: "receipt.fill",
                tint: .teal
            )
        }
    }

    private var entryCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label("New expense", systemImage: "plus.circle.fill")
                    .font(.headline)

                HStack(alignment: .bottom, spacing: 12) {
                    ledgerField(title: "Purpose") {
                        TextField("Coffee, groceries, subscription…", text: $purpose)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .purpose)
                            .onSubmit { focusedField = .amount }
                    }

                    ledgerField(title: "Amount") {
                        HStack(spacing: 6) {
                            Text(LedgerStore.moneySymbol)
                                .foregroundStyle(.secondary)
                            TextField("0.00", text: $amount)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 130)
                                .focused($focusedField, equals: .amount)
                                .onSubmit(addExpense)
                                .onChange(of: amount) { _, newValue in
                                    let sanitized = LedgerStore.sanitizedAmountInput(newValue)
                                    if sanitized != newValue { amount = sanitized }
                                }
                        }
                    }

                    Button(action: addExpense) {
                        Label("Add Expense", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canAdd)
                }
            }
            .padding(8)
            .disabled(store.isBusy || !store.hasLoaded)
        }
    }

    private var recordsCard: some View {
        GroupBox {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Expense history")
                            .font(.headline)
                        Text("Oldest records appear first")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: createImage) {
                        Label(
                            didCopyImage ? "Copied" : "Print Bill",
                            systemImage: didCopyImage ? "checkmark" : "printer"
                        )
                    }
                    .disabled(store.records.isEmpty || store.isBusy)
                    Button("Clear All", role: .destructive) {
                        showClearConfirmation = true
                    }
                    .disabled(store.records.isEmpty || store.isBusy)
                }
                .padding(8)

                Divider().padding(.top, 8)

                if store.records.isEmpty {
                    ContentUnavailableView(
                        store.hasLoaded ? "No expenses yet" : "Expenses not loaded",
                        systemImage: "tray",
                        description: Text(store.hasLoaded ? "Add your first expense above to start the ledger." : "Connect to the backend and refresh to load your expenses.")
                    )
                    .frame(minHeight: 210)
                } else {
                    tableHeader
                    ForEach(store.records) { record in
                        Divider()
                        ExpenseRowView(
                            record: record,
                            onRename: { newPurpose in
                                let didUpdate = await store.updatePurpose(
                                    id: record.id,
                                    purpose: newPurpose
                                )
                                if didUpdate { didCopyImage = false }
                                return didUpdate
                            },
                            onDelete: {
                                Task {
                                    if await store.delete(id: record.id) { didCopyImage = false }
                                }
                            }
                        )
                        .disabled(store.isBusy)
                    }
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 16) {
            Text("PURPOSE").frame(maxWidth: .infinity, alignment: .leading)
            Text("CREATED").frame(width: 190, alignment: .leading)
            Text("AMOUNT").frame(width: 130, alignment: .trailing)
            Color.clear.frame(width: 62)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.secondary.opacity(0.06))
    }

    private func summaryTile(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15)))
    }

    private func ledgerField<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: title == "Purpose" ? .infinity : nil, alignment: .leading)
    }

    private var canAdd: Bool {
        !store.isBusy && store.hasLoaded && !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (LedgerStore.cents(from: amount) ?? 0) > 0
    }

    private func addExpense() {
        guard canAdd else { return }
        Task {
            guard await store.add(purpose: purpose, amountText: amount) else { return }
            purpose = ""
            amount = ""
            didCopyImage = false
            focusedField = .purpose
        }
    }

    private func formattedAmount(_ cents: Int64) -> String {
        LedgerStore.formattedAmount(cents)
    }

    private var imageErrorIsPresented: Binding<Bool> {
        Binding(
            get: { imageError != nil },
            set: { if !$0 { imageError = nil } }
        )
    }

    private func createImage() {
        guard !store.records.isEmpty else { return }
        let image = InvoiceImageRenderer.makeImage(
            records: store.records
        )
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.writeObjects([image]) {
            didCopyImage = true
        } else {
            imageError = "JasonApp could not place the generated image on the clipboard."
        }
    }
}

private struct ExpenseRowView: View {
    let record: ExpenseRecord
    let onRename: (String) async -> Bool
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var isEditing = false
    @State private var draftPurpose = ""
    @FocusState private var isPurposeFocused: Bool

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "cart.fill")
                    .font(.caption)
                    .foregroundStyle(.indigo)
                    .frame(width: 28, height: 28)
                    .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

                if isEditing {
                    TextField("Purpose", text: $draftPurpose)
                        .textFieldStyle(.roundedBorder)
                        .focused($isPurposeFocused)
                        .onSubmit(saveEdit)
                } else {
                    Text(record.purpose)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .onTapGesture(count: 2, perform: beginEditing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(InvoiceImageRenderer.dateText(for: record.createdAt))
                .foregroundStyle(.secondary)
                .frame(width: 190, alignment: .leading)

            Text(formattedAmount)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .frame(width: 130, alignment: .trailing)

            actionButtons
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .background(isHovering ? Color.accentColor.opacity(0.045) : .clear)
        .onHover { isHovering = $0 }
        .onChange(of: isEditing) { _, editing in
            if editing { isPurposeFocused = true }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if isEditing {
            HStack(spacing: 5) {
                iconButton("checkmark", help: "Save purpose", action: saveEdit)
                    .disabled(trimmedDraft.isEmpty)
                iconButton("xmark", help: "Cancel editing", action: cancelEdit)
            }
        } else if isHovering {
            HStack(spacing: 5) {
                iconButton("pencil", help: "Edit purpose", action: beginEditing)
                iconButton("trash", help: "Delete expense", tint: .red, action: onDelete)
            }
            .transition(.opacity)
        }
    }

    private func iconButton(
        _ icon: String,
        help: String,
        tint: Color = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .help(help)
    }

    private var trimmedDraft: String {
        draftPurpose.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var formattedAmount: String {
        LedgerStore.formattedAmount(record.amountInCents)
    }

    private func beginEditing() {
        draftPurpose = record.purpose
        isEditing = true
    }

    private func saveEdit() {
        Task {
            if await onRename(draftPurpose) { isEditing = false }
        }
    }

    private func cancelEdit() {
        draftPurpose = record.purpose
        isEditing = false
    }
}
