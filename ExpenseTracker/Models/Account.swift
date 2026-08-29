import Foundation
import SwiftData

@Model
final class Account {

    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = AccountKind.bank.rawValue
    /// Balance the account had before any transaction in this app was recorded.
    var openingBalance: Decimal = Decimal.zero
    var colorHex: String = Theme.paletteHexes[0]
    var symbolName: String = AccountKind.bank.symbolName
    var isArchived: Bool = false
    var sortIndex: Int = 0
    var note: String = ""
    var createdAt: Date = Date()

    /// Deleting an account removes its transactions — the UI warns before this happens.
    @Relationship(deleteRule: .cascade, inverse: \Transaction.account)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringRule.account)
    var recurringRules: [RecurringRule]? = []

    /// Creates an account.
    /// - Parameters:
    ///   - id: Stable identifier; a fresh UUID unless restoring from a backup.
    ///   - name: Display name.
    ///   - kind: Bank, credit or cash — decides liability handling.
    ///   - openingBalance: Balance before any transaction recorded here.
    ///   - colorHex: Accent colour; defaults to the first palette entry.
    ///   - symbolName: SF Symbol override; defaults to the kind's symbol.
    ///   - sortIndex: Position in the accounts list.
    ///   - note: Free-text note.
    ///   - createdAt: Creation timestamp.
    init(
        id: UUID = UUID(),
        name: String,
        kind: AccountKind,
        openingBalance: Decimal = .zero,
        colorHex: String = Theme.paletteHexes[0],
        symbolName: String? = nil,
        sortIndex: Int = 0,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.openingBalance = openingBalance
        self.colorHex = colorHex
        self.symbolName = symbolName ?? kind.symbolName
        self.isArchived = false
        self.sortIndex = sortIndex
        self.note = note
        self.createdAt = createdAt
    }

    /// Typed view of `kindRaw`; falls back to `.bank` on an unknown value.
    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .bank }
        set { kindRaw = newValue.rawValue }
    }

    /// Opening balance plus every posted transaction. Expenses subtract, income adds.
    var currentBalance: Decimal {
        (transactions ?? []).reduce(openingBalance) { $0 + $1.signedAmount }
    }

    /// Balance counting only transactions dated today or earlier.
    var clearedBalance: Decimal {
        let cutoff = Date.now.endOfDay
        return (transactions ?? [])
            .filter { $0.date <= cutoff }
            .reduce(openingBalance) { $0 + $1.signedAmount }
    }
}
