import AppKit
import Foundation
import Testing
@testable import JasonUI

actor StubLedgerAPI: LedgerAPI {
    var records: [ExpenseRecord]
    var failSave = false
    var failDeleteID: String?

    init(records: [ExpenseRecord] = []) { self.records = records }
    func setFailSave() { failSave = true }
    func setFailDelete(_ id: String) { failDeleteID = id }
    func expenses() async throws -> [ExpenseRecord] { records }
    func createExpense(amount: Decimal, description: String) async throws -> ExpenseRecord {
        if failSave { throw APIError.server(statusCode: 503, message: "Unavailable") }
        let record = try LedgerExpenseResponse(id: "10-27-2026:1", amount: amount, description: description).record()
        records.append(record)
        return record
    }
    func renameExpense(id: String, description: String) async throws -> ExpenseRecord {
        if failSave { throw APIError.server(statusCode: 503, message: "Unavailable") }
        let old = records.first { $0.id == id }!
        let record = ExpenseRecord(id: id, purpose: description, amountInCents: old.amountInCents, createdAt: old.createdAt)
        records = records.map { $0.id == id ? record : $0 }
        return record
    }
    func deleteExpense(id: String) async throws {
        if id == failDeleteID { throw APIError.server(statusCode: 503, message: "Unavailable") }
        records.removeAll { $0.id == id }
    }
}

@MainActor
struct LedgerStoreTests {
    @Test func savesToBackendAndReloads() async {
        let api = StubLedgerAPI()
        let store = LedgerStore()
        await store.load(using: api)
        #expect(await store.add(purpose: "  Groceries  ", amountText: "12.34"))
        #expect(store.records.first?.id == "10-27-2026:1")
        #expect(store.records.first?.purpose == "Groceries")
        #expect(store.totalInCents == 1234)
        let restored = LedgerStore()
        await restored.load(using: api)
        #expect(restored.records == store.records)
    }

    @Test func sortsAcrossYearsAndCountersNumerically() async throws {
        let records = try ["01-01-2026:10", "01-01-2026:2", "12-31-2025:1"].map {
            try LedgerExpenseResponse(id: $0, amount: 1, description: $0).record()
        }
        let store = LedgerStore()
        await store.load(using: StubLedgerAPI(records: records))
        #expect(store.records.map(\.id) == ["12-31-2025:1", "01-01-2026:2", "01-01-2026:10"])
    }

    @Test func failedSavePreservesConfirmedRecords() async {
        let api = StubLedgerAPI()
        let store = LedgerStore()
        await store.load(using: api)
        #expect(await store.add(purpose: "Coffee", amountText: "4.50"))
        let confirmed = store.records
        await api.setFailSave()
        #expect(!(await store.add(purpose: "Lunch", amountText: "12")))
        #expect(!(await store.updatePurpose(id: confirmed[0].id, purpose: "Changed")))
        #expect(store.records == confirmed)
        #expect(store.errorMessage != nil)
        #expect(!store.isBusy)
    }

    @Test func rejectsInvalidInputsAndRequiresLoad() async {
        let store = LedgerStore()
        #expect(!(await store.add(purpose: "Lunch", amountText: "10")))
        await store.load(using: StubLedgerAPI())
        #expect(!(await store.add(purpose: "", amountText: "10")))
        #expect(!(await store.add(purpose: "Lunch", amountText: "0")))
        #expect(!(await store.add(purpose: "Lunch", amountText: "not money")))
        #expect(store.records.isEmpty)
    }

    @Test func clearsOnlySuccessfullyDeletedRecordsOnPartialFailure() async throws {
        let records = try ["01-01-2026:1", "01-01-2026:2", "01-01-2026:3"].map {
            try LedgerExpenseResponse(id: $0, amount: 1, description: $0).record()
        }
        let api = StubLedgerAPI(records: records)
        await api.setFailDelete("01-01-2026:2")
        let store = LedgerStore()
        await store.load(using: api)
        #expect(!(await store.clear()))
        #expect(store.records.map(\.id) == ["01-01-2026:2", "01-01-2026:3"])
        #expect(store.errorMessage != nil)
    }

    @Test func renamesAndDeletesOnBackend() async {
        let api = StubLedgerAPI()
        let store = LedgerStore()
        await store.load(using: api)
        #expect(await store.add(purpose: "Old", amountText: "12"))
        #expect(await store.updatePurpose(id: "10-27-2026:1", purpose: "  New  "))
        #expect(store.records.first?.purpose == "New")
        #expect(await store.delete(id: "10-27-2026:1"))
        #expect(store.records.isEmpty)
        let remote = try? await api.expenses()
        #expect(remote?.isEmpty == true)
    }

    @Test func amountInputAllowsOnlyMoneyCharacters() {
        #expect(LedgerStore.sanitizedAmountInput("abc12x.3z4") == "12.34")
        #expect(LedgerStore.sanitizedAmountInput("9.876") == "9.87")
        #expect(LedgerStore.sanitizedAmountInput("1.2.3") == "1.23")
        #expect(LedgerStore.sanitizedAmountInput("coffee") == "")
        #expect(LedgerStore.cents(from: "💰12.34") == 1234)
        #expect(LedgerStore.cents(from: "1.234") == nil)
        #expect(LedgerStore.cents(from: "999999999999999999999") == nil)
        #expect(LedgerStore.formattedAmount(1234) == "💰12.34")
    }

    @Test func createsLedgerImageWithRequestedDateFormat() throws {
        let record = try LedgerExpenseResponse(id: "11-14-2023:1", amount: Decimal(string: "42.50")!, description: "Team lunch").record()
        let image = InvoiceImageRenderer.makeImage(records: [record])
        let tiffData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiffData))
        #expect(image.size.width == 1200)
        #expect(bitmap.pixelsWide >= 1200)
        #expect(InvoiceImageRenderer.dateText(for: record.createdAt) == "2023-11-14")
    }
}
