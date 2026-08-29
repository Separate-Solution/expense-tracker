import Foundation
import SwiftData

@Model
final class Category {

    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "🏷️"
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

    /// Creates a category.
    /// - Parameters:
    ///   - id: Stable identifier; a fresh UUID unless restoring from a backup.
    ///   - name: Display name.
    ///   - emoji: Badge glyph.
    ///   - colorHex: Badge colour; defaults to the first palette entry.
    ///   - type: Whether it groups expenses or income.
    ///   - sortIndex: Position within its type's list.
    ///   - createdAt: Creation timestamp.
    init(
        id: UUID = UUID(),
        name: String,
        emoji: String = "🏷️",
        colorHex: String = Theme.paletteHexes[0],
        type: TransactionType,
        sortIndex: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.typeRaw = type.rawValue
        self.isArchived = false
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }

    /// Typed view of `typeRaw`; falls back to `.expense` on an unknown value.
    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }
}
