import Foundation

struct ExpenseRecord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let purpose: String
    let amountInCents: Int64
    let createdAt: Date

    var dailyCounter: Int { Int(id.split(separator: ":").last ?? "") ?? 0 }
}

/// Firestore stores amounts as doubles in currency units; calculations use cents.
struct LedgerExpenseResponse: Decodable {
    let id: String
    let amount: Decimal
    let description: String

    func record() throws -> ExpenseRecord {
        let parts = id.split(separator: ":")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM-dd-yyyy"
        formatter.isLenient = false
        guard parts.count == 2, let counter = Int(parts[1]), counter > 0,
              let date = formatter.date(from: String(parts[0])),
              formatter.string(from: date) == String(parts[0]),
              amount > 0, amount <= Decimal(string: "999999999.99")! else {
            throw APIError.invalidResponse
        }
        let cents = amount * 100
        var source = cents
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        guard cents == rounded else { throw APIError.invalidResponse }
        return ExpenseRecord(
            id: id, purpose: description,
            amountInCents: NSDecimalNumber(decimal: rounded).int64Value,
            createdAt: date
        )
    }
}

struct LedgerExpenseList: Decodable {
    let expenses: [LedgerExpenseResponse]
}

protocol LedgerAPI: Sendable {
    func expenses() async throws -> [ExpenseRecord]
    func createExpense(amount: Decimal, description: String) async throws -> ExpenseRecord
    func renameExpense(id: String, description: String) async throws -> ExpenseRecord
    func deleteExpense(id: String) async throws
}

extension APIClient: LedgerAPI {
    // Implementations live beside the client's shared request helpers.
}
