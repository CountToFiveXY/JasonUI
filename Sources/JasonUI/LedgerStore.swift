import Foundation
import Observation

@MainActor
@Observable
final class LedgerStore {
    nonisolated static let moneySymbol = "💰"
    private(set) var records: [ExpenseRecord] = []
    private(set) var isBusy = false
    private(set) var hasLoaded = false
    var errorMessage: String?
    @ObservationIgnored private var api: (any LedgerAPI)?

    var totalInCents: Int64 { records.reduce(0) { $0 + $1.amountInCents } }

    func load(using api: (any LedgerAPI)?) async {
        guard !isBusy else { return }
        self.api = api
        guard let api else {
            errorMessage = APIError.invalidBaseURL.localizedDescription
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            records = try await api.expenses()
            sortRecords()
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func add(purpose: String, amountText: String) async -> Bool {
        let description = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty, let cents = Self.cents(from: amountText),
              cents > 0, cents <= 99_999_999_999 else { return false }
        return await perform { api in
            let record = try await api.createExpense(amount: Decimal(cents) / 100, description: description)
            self.records.append(record)
            self.sortRecords()
        }
    }

    @discardableResult
    func updatePurpose(id: String, purpose: String) async -> Bool {
        let description = purpose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return false }
        return await perform { api in
            let updated = try await api.renameExpense(id: id, description: description)
            if let index = self.records.firstIndex(where: { $0.id == id }) {
                self.records[index] = updated
            }
        }
    }

    @discardableResult
    func delete(id: String) async -> Bool {
        await perform { api in
            try await api.deleteExpense(id: id)
            self.records.removeAll { $0.id == id }
        }
    }

    @discardableResult
    func clear() async -> Bool {
        // Delete only the displayed snapshot; leave newly created remote records alone.
        let ids = records.map(\.id)
        return await perform { api in
            for id in ids {
                try await api.deleteExpense(id: id)
                self.records.removeAll { $0.id == id }
            }
        }
    }

    private func perform(_ operation: (any LedgerAPI) async throws -> Void) async -> Bool {
        guard !isBusy, hasLoaded, let api else { return false }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await operation(api)
            return true
        } catch {
            errorMessage = error.localizedDescription + " Refresh the list before retrying."
            return false
        }
    }

    private func sortRecords() {
        records.sort {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.dailyCounter < $1.dailyCounter
        }
    }

    nonisolated static func cents(from text: String) -> Int64? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: moneySymbol, with: "")
        value = value.replacingOccurrences(of: Locale.current.currencySymbol ?? "$", with: "")
        value = value.replacingOccurrences(of: ",", with: "")
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")),
              decimal > 0, decimal <= Decimal(string: "999999999.99")! else { return nil }

        var source = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        guard source == rounded else { return nil }
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

}
