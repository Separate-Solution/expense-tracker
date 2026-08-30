import Foundation
import SwiftData

@Model
final class Category {

    var id: UUID = UUID()
    var name: String = ""
    /// SF Symbol shown on the category badge. Empty on rows written before
    /// categories moved off emoji; `symbol` fills that gap.
    var symbolName: String = ""
    /// The glyph categories used to carry. Nothing renders it any more — it is
    /// kept so an upgraded store and older backups can still be read.
    var emoji: String = ""
    var colorHex: String = Theme.paletteHexes[0]
    var typeRaw: String = TransactionType.expense.rawValue
    var isArchived: Bool = false
    var sortIndex: Int = 0
    var createdAt: Date = Date()

    /// Transactions keep their history when a category is deleted; they become "Uncategorized".
    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringRule.category)
    var recurringRules: [RecurringRule]? = []

    /// Budgets counting this category, when they count categories by hand.
    var includingBudgets: [Budget]? = []

    /// Budgets that leave this category out of whatever else they count.
    var excludingBudgets: [Budget]? = []

    /// Creates a category.
    /// - Parameters:
    ///   - id: Stable identifier; a fresh UUID unless restoring from a backup.
    ///   - name: Display name.
    ///   - symbol: SF Symbol for the badge; inferred from the name when nil.
    ///   - emoji: Legacy glyph, only passed when reading an older backup.
    ///   - colorHex: Badge colour; defaults to the first palette entry.
    ///   - type: Whether it groups expenses or income.
    ///   - sortIndex: Position within its type's list.
    ///   - createdAt: Creation timestamp.
    init(
        id: UUID = UUID(),
        name: String,
        symbol: String? = nil,
        emoji: String = "",
        colorHex: String = Theme.paletteHexes[0],
        type: TransactionType,
        sortIndex: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbol ?? CategoryIcon.inferred(name: name, emoji: emoji, type: type)
        self.emoji = emoji
        self.colorHex = colorHex
        self.typeRaw = type.rawValue
        self.isArchived = false
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }

    /// The symbol to render. Rows from before the icon change have no
    /// `symbolName`, so one is derived from their old glyph or their name.
    var symbol: String {
        symbolName.isEmpty
            ? CategoryIcon.inferred(name: name, emoji: emoji, type: type)
            : symbolName
    }

    /// Typed view of `typeRaw`; falls back to `.expense` on an unknown value.
    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }
}
