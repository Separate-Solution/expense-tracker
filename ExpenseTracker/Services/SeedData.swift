import Foundation
import SwiftData

/// First-launch content so the app is usable immediately instead of showing
/// an empty category grid on the very first transaction.
enum SeedData {

    struct CategorySeed {
        let name: String
        let symbol: String
        let colorIndex: Int
    }

    static let expenseCategories: [CategorySeed] = [
        .init(name: "Groceries", symbol: "cart.fill", colorIndex: 9),
        .init(name: "Dining", symbol: "fork.knife", colorIndex: 11),
        .init(name: "Transport", symbol: "car.fill", colorIndex: 0),
        .init(name: "Shopping", symbol: "bag.fill", colorIndex: 6),
        .init(name: "Bills & Utilities", symbol: "lightbulb.fill", colorIndex: 3),
        .init(name: "Rent", symbol: "house.fill", colorIndex: 8),
        .init(name: "Health", symbol: "cross.case.fill", colorIndex: 1),
        .init(name: "Entertainment", symbol: "film.fill", colorIndex: 4),
        .init(name: "Subscriptions", symbol: "arrow.triangle.2.circlepath", colorIndex: 5),
        .init(name: "Travel", symbol: "airplane", colorIndex: 10),
        .init(name: "Education", symbol: "graduationcap.fill", colorIndex: 2),
        .init(name: "Personal Care", symbol: "sparkles", colorIndex: 6),
        .init(name: "Gifts", symbol: "gift.fill", colorIndex: 4),
        .init(name: "Other", symbol: "shippingbox.fill", colorIndex: 8)
    ]

    static let incomeCategories: [CategorySeed] = [
        .init(name: "Salary", symbol: "briefcase.fill", colorIndex: 9),
        .init(name: "Freelance", symbol: "laptopcomputer", colorIndex: 0),
        .init(name: "Business", symbol: "building.2.fill", colorIndex: 5),
        .init(name: "Investments", symbol: "chart.line.uptrend.xyaxis", colorIndex: 2),
        .init(name: "Interest", symbol: "building.columns.fill", colorIndex: 3),
        .init(name: "Refunds", symbol: "arrow.uturn.left.circle.fill", colorIndex: 8),
        .init(name: "Other", symbol: "banknote.fill", colorIndex: 4)
    ]

    /// Inserts defaults only when the store is genuinely empty, so a restore
    /// or a CSV import never gets duplicate categories bolted on.
    static func seedIfNeeded(in context: ModelContext) {
        let categoryCount = (try? context.fetchCount(FetchDescriptor<Category>())) ?? 0
        if categoryCount == 0 {
            insertDefaultCategories(in: context)
        }

        backfillCategoryIcons(in: context)
        migrateLegacyCreditAccounts(in: context)

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

    /// Inserts the built-in expense and income categories without saving.
    /// Called on first launch and again after an erase.
    /// - Parameter context: The context to insert into; the caller saves.
    static func insertDefaultCategories(in context: ModelContext) {
        for (index, seed) in expenseCategories.enumerated() {
            context.insert(Category(
                name: seed.name,
                symbol: seed.symbol,
                colorHex: Theme.paletteHexes[seed.colorIndex % Theme.paletteHexes.count],
                type: .expense,
                sortIndex: index
            ))
        }
        for (index, seed) in incomeCategories.enumerated() {
            context.insert(Category(
                name: seed.name,
                symbol: seed.symbol,
                colorHex: Theme.paletteHexes[seed.colorIndex % Theme.paletteHexes.count],
                type: .income,
                sortIndex: index
            ))
        }
    }

    /// Converts accounts saved with the retired `.credit` kind into real
    /// `CreditCard` records, keeping their name, colour, note and full history.
    ///
    /// The card starts with no credit limit — the app never knew one — so the
    /// cards list flags it until the user fills it in. Transactions are moved
    /// across before the account is deleted, so its cascade rule cannot take
    /// them with it. A no-op once no legacy account is left.
    /// - Parameter context: The context to update; the caller saves.
    static func migrateLegacyCreditAccounts(in context: ModelContext) {
        let creditRaw = AccountKind.credit.rawValue
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.kindRaw == creditRaw }
        )
        guard let legacy = try? context.fetch(descriptor), !legacy.isEmpty else { return }

        let existingCards = (try? context.fetch(FetchDescriptor<CreditCard>())) ?? []
        var nextSortIndex = (existingCards.map(\.sortIndex).max() ?? -1) + 1

        for account in legacy {
            let card = CreditCard(
                id: account.id,
                name: account.name,
                creditLimit: .zero,
                statementDay: 1,
                dueDay: 20,
                // A credit account held what you owed as a negative balance, so
                // the sign flips: outstanding counts up as you spend.
                openingOutstanding: -account.openingBalance,
                colorHex: account.colorHex,
                sortIndex: nextSortIndex,
                note: account.note,
                createdAt: account.createdAt
            )
            card.isArchived = account.isArchived
            context.insert(card)
            nextSortIndex += 1

            for transaction in account.transactions ?? [] {
                transaction.account = nil
                transaction.creditCard = card
            }
            for rule in account.recurringRules ?? [] {
                rule.account = nil
                rule.creditCard = card
            }

            context.delete(account)
        }
    }

    /// Gives an SF Symbol to categories saved before icons stopped being
    /// emoji, deriving it from the old glyph and falling back to the name.
    /// A no-op once every category has one.
    /// - Parameter context: The context to update; the caller saves.
    static func backfillCategoryIcons(in context: ModelContext) {
        let stale = FetchDescriptor<Category>(
            predicate: #Predicate { $0.symbolName.isEmpty }
        )
        guard let categories = try? context.fetch(stale), !categories.isEmpty else { return }
        for category in categories {
            category.symbolName = CategoryIcon.inferred(
                name: category.name,
                emoji: category.emoji,
                type: category.type
            )
        }
    }
}
