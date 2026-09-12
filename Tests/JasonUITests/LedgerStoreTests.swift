import AppKit
import Foundation
import Testing
@testable import JasonUI

@MainActor
struct LedgerStoreTests {
    @Test func addsExpenseAndPersistsIt() {
        let suite = "LedgerStoreTests.add.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "expenses"
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let store = LedgerStore(defaults: defaults, storageKey: key)
        #expect(store.add(purpose: "  Groceries  ", amountText: "12.34", createdAt: date))
        #expect(store.records.first?.purpose == "Groceries")
        #expect(store.records.first?.amountInCents == 1_234)
        #expect(store.totalInCents == 1_234)

        let restored = LedgerStore(defaults: defaults, storageKey: key)
        #expect(restored.records == store.records)
    }

    @Test func ordersExpensesByCreationTimeAscending() {
        let defaults = UserDefaults(suiteName: "LedgerStoreTests.order.\(UUID().uuidString)")!
        let store = LedgerStore(defaults: defaults, storageKey: "expenses")
        let newer = Date(timeIntervalSince1970: 2_000)
        let older = Date(timeIntervalSince1970: 1_000)

        #expect(store.add(purpose: "Newer", amountText: "20", createdAt: newer))
        #expect(store.add(purpose: "Older", amountText: "10", createdAt: older))

        #expect(store.records.map(\.purpose) == ["Older", "Newer"])
    }

    @Test func rejectsIncompleteOrInvalidExpenses() {
        let defaults = UserDefaults(suiteName: "LedgerStoreTests.invalid.\(UUID().uuidString)")!
        let store = LedgerStore(defaults: defaults, storageKey: "expenses")

        #expect(!store.add(purpose: "", amountText: "10"))
        #expect(!store.add(purpose: "Lunch", amountText: "0"))
        #expect(!store.add(purpose: "Lunch", amountText: "not money"))
        #expect(store.records.isEmpty)
    }

    @Test func amountInputAllowsOnlyMoneyCharacters() {
        #expect(LedgerStore.sanitizedAmountInput("abc12x.3z4") == "12.34")
        #expect(LedgerStore.sanitizedAmountInput("9.876") == "9.87")
        #expect(LedgerStore.sanitizedAmountInput("1.2.3") == "1.23")
        #expect(LedgerStore.sanitizedAmountInput("coffee") == "")
    }

    @Test func clearsEveryRecord() {
        let defaults = UserDefaults(suiteName: "LedgerStoreTests.clear.\(UUID().uuidString)")!
        let store = LedgerStore(defaults: defaults, storageKey: "expenses")
        #expect(store.add(purpose: "Coffee", amountText: "$4.50"))

        store.clear()

        #expect(store.records.isEmpty)
        #expect(store.totalInCents == 0)
    }

    @Test func renamesAndDeletesIndividualExpenses() throws {
        let suite = "LedgerStoreTests.edit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LedgerStore(defaults: defaults, storageKey: "expenses")
        #expect(store.add(purpose: "Old purpose", amountText: "12"))
        let id = try #require(store.records.first?.id)

        #expect(store.updatePurpose(id: id, purpose: "  New purpose  "))
        #expect(store.records.first?.purpose == "New purpose")
        #expect(!store.updatePurpose(id: id, purpose: "   "))

        let restored = LedgerStore(defaults: defaults, storageKey: "expenses")
        #expect(restored.records.first?.purpose == "New purpose")
        restored.delete(id: id)
        #expect(restored.records.isEmpty)
    }

    @Test func createsLedgerImageWithRequestedDateFormat() throws {
        let records = [
            ExpenseRecord(
                id: UUID(),
                purpose: "Team lunch",
                amountInCents: 4_250,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]

        let image = InvoiceImageRenderer.makeImage(
            records: records,
            currencyCode: "USD"
        )
        let tiffData = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiffData))

        #expect(image.size.width == 1_200)
        #expect(image.size.height >= 566)
        #expect(bitmap.pixelsWide >= 1_200)
        #expect(InvoiceImageRenderer.dateText(for: records[0].createdAt) == "2023-11-14")
    }
}
