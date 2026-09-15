import AppKit
import Foundation
import Observation
import SwiftUI

struct ExpenseRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let purpose: String
    let amountInCents: Int64
    let createdAt: Date
}

@MainActor
@Observable
final class LedgerStore {
    nonisolated static let moneySymbol = "💰"

    private(set) var records: [ExpenseRecord]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "ledger.expenses") {
        self.defaults = defaults
        self.storageKey = storageKey
        records = Self.load(from: defaults, key: storageKey)
    }

    var totalInCents: Int64 {
        records.reduce(0) { $0 + $1.amountInCents }
    }

    @discardableResult
    func add(purpose: String, amountText: String, createdAt: Date = .now) -> Bool {
        let cleanPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPurpose.isEmpty,
              let cents = Self.cents(from: amountText),
              cents > 0 else { return false }

        records.append(
            ExpenseRecord(
                id: UUID(),
                purpose: cleanPurpose,
                amountInCents: cents,
                createdAt: createdAt
            )
        )
        records.sort { $0.createdAt < $1.createdAt }
        save()
        return true
    }

    func clear() {
        records.removeAll()
        save()
    }

    @discardableResult
    func updatePurpose(id: UUID, purpose: String) -> Bool {
        let cleanPurpose = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPurpose.isEmpty,
              let index = records.firstIndex(where: { $0.id == id }) else { return false }
        let existing = records[index]
        records[index] = ExpenseRecord(
            id: existing.id,
            purpose: cleanPurpose,
            amountInCents: existing.amountInCents,
            createdAt: existing.createdAt
        )
        save()
        return true
    }

    func delete(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    nonisolated static func cents(from text: String) -> Int64? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: moneySymbol, with: "")
        value = value.replacingOccurrences(of: Locale.current.currencySymbol ?? "$", with: "")
        value = value.replacingOccurrences(of: ",", with: "")
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              decimal > 0 else { return nil }

        var source = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    /// Keeps expense input monetary: digits, one decimal point, and two cents digits.
    nonisolated static func sanitizedAmountInput(_ text: String) -> String {
        var result = ""
        var hasDecimalPoint = false
        var fractionDigits = 0

        for character in text {
            if let digit = character.wholeNumberValue {
                if hasDecimalPoint {
                    guard fractionDigits < 2 else { continue }
                    fractionDigits += 1
                }
                result.append(String(digit))
            } else if character == ".", !hasDecimalPoint {
                hasDecimalPoint = true
                result.append(character)
            }
        }
        return result
    }

    nonisolated static func formattedAmount(_ cents: Int64) -> String {
        moneySymbol + (Decimal(cents) / 100).formatted(
            .number.precision(.fractionLength(2))
        )
    }

    private static func load(from defaults: UserDefaults, key: String) -> [ExpenseRecord] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ExpenseRecord].self, from: data) else {
            return []
        }
        return decoded.sorted { $0.createdAt < $1.createdAt }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct LedgerView: View {
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
                overview
                entryCard
                recordsCard
            }
            .frame(maxWidth: 900, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .navigationTitle("Expense Ledger")
        .alert("Clear every expense?", isPresented: $showClearConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) { store.clear() }
        } message: {
            Text("This permanently removes all \(store.records.count) records from this Mac.")
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
                    .disabled(store.records.isEmpty)
                    Button("Clear All", role: .destructive) {
                        showClearConfirmation = true
                    }
                    .disabled(store.records.isEmpty)
                }
                .padding(8)

                Divider().padding(.top, 8)

                if store.records.isEmpty {
                    ContentUnavailableView(
                        "No expenses yet",
                        systemImage: "tray",
                        description: Text("Add your first expense above to start the ledger.")
                    )
                    .frame(minHeight: 210)
                } else {
                    tableHeader
                    ForEach(store.records) { record in
                        Divider()
                        ExpenseRowView(
                            record: record,
                            onRename: { newPurpose in
                                let didUpdate = store.updatePurpose(
                                    id: record.id,
                                    purpose: newPurpose
                                )
                                if didUpdate { didCopyImage = false }
                                return didUpdate
                            },
                            onDelete: {
                                store.delete(id: record.id)
                                didCopyImage = false
                            }
                        )
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
        !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (LedgerStore.cents(from: amount) ?? 0) > 0
    }

    private func addExpense() {
        guard store.add(purpose: purpose, amountText: amount) else { return }
        purpose = ""
        amount = ""
        didCopyImage = false
        focusedField = .purpose
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
    let onRename: (String) -> Bool
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

            Text(record.createdAt, format: .iso8601.year().month().day())
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
        if onRename(draftPurpose) {
            isEditing = false
        }
    }

    private func cancelEdit() {
        draftPurpose = record.purpose
        isEditing = false
    }
}
