import Foundation
import SwiftData

/// First-launch content so the app is usable immediately instead of showing
/// an empty category grid on the very first transaction.
enum SeedData {

    struct CategorySeed {
        let name: String
        let emoji: String
        let colorIndex: Int
    }

    static let expenseCategories: [CategorySeed] = [
        .init(name: "Groceries", emoji: "🛒", colorIndex: 9),
        .init(name: "Dining", emoji: "🍔", colorIndex: 11),
        .init(name: "Transport", emoji: "🚕", colorIndex: 0),
        .init(name: "Shopping", emoji: "🛍️", colorIndex: 6),
        .init(name: "Bills & Utilities", emoji: "💡", colorIndex: 3),
        .init(name: "Rent", emoji: "🏠", colorIndex: 8),
        .init(name: "Health", emoji: "💊", colorIndex: 1),
        .init(name: "Entertainment", emoji: "🎬", colorIndex: 4),
        .init(name: "Subscriptions", emoji: "🔁", colorIndex: 5),
        .init(name: "Travel", emoji: "✈️", colorIndex: 10),
        .init(name: "Education", emoji: "📚", colorIndex: 2),
        .init(name: "Personal Care", emoji: "🧴", colorIndex: 6),
        .init(name: "Gifts", emoji: "🎁", colorIndex: 4),
        .init(name: "Other", emoji: "📦", colorIndex: 8)
    ]

    static let incomeCategories: [CategorySeed] = [
        .init(name: "Salary", emoji: "💼", colorIndex: 9),
        .init(name: "Freelance", emoji: "🧑‍💻", colorIndex: 0),
        .init(name: "Business", emoji: "🏢", colorIndex: 5),
        .init(name: "Investments", emoji: "📈", colorIndex: 2),
        .init(name: "Interest", emoji: "🏦", colorIndex: 3),
        .init(name: "Refunds", emoji: "↩️", colorIndex: 8),
        .init(name: "Other", emoji: "💰", colorIndex: 4)
    ]

    /// Inserts defaults only when the store is genuinely empty, so a restore
    /// or a CSV import never gets duplicate categories bolted on.
    static func seedIfNeeded(in context: ModelContext) {
        let categoryCount = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        if categoryCount == 0 {
            insertDefaultCategories(in: context)
        }

        let accountCount = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        if accountCount == 0 {
            context.insert(Account(
                name: "Cash",
                kind: .cash,
                colorHex: Theme.paletteHexes[9],
                sortIndex: 0
            ))
        }

        try? context.save()
    }

    static func insertDefaultCategories(in context: ModelContext) {
        for (index, seed) in expenseCategories.enumerated() {
            context.insert(Category(
                name: seed.name,
                emoji: seed.emoji,
                colorHex: Theme.paletteHexes[seed.colorIndex % Theme.paletteHexes.count],
                type: .expense,
                sortIndex: index
            ))
        }
        for (index, seed) in incomeCategories.enumerated() {
            context.insert(Category(
                name: seed.name,
                emoji: seed.emoji,
                colorHex: Theme.paletteHexes[seed.colorIndex % Theme.paletteHexes.count],
                type: .income,
                sortIndex: index
            ))
        }
    }
}
