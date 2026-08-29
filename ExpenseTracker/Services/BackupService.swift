import Foundation
import SwiftData

/// Full-fidelity local backup: every account, category, rule and transaction in
/// one JSON file, with relationships stored as IDs so restore can rebuild them.
struct BackupPayload: Codable {
    static let currentFormatVersion = 1

    var formatVersion: Int = BackupPayload.currentFormatVersion
    var exportedAt: Date = Date()
    var appVersion: String = ""
    var currencyCode: String = ""
    var accounts: [AccountDTO] = []
    var categories: [CategoryDTO] = []
    var recurringRules: [RecurringRuleDTO] = []
    var transactions: [TransactionDTO] = []

    struct AccountDTO: Codable {
        var id: UUID
        var name: String
        var kind: String
        var openingBalance: Decimal
        var colorHex: String
        var symbolName: String
        var isArchived: Bool
        var sortIndex: Int
        var note: String
        var createdAt: Date
    }

    struct CategoryDTO: Codable {
        var id: UUID
        var name: String
        /// Absent in backups written before categories used SF Symbols.
        var symbolName: String?
        /// Only present in those older backups; used to infer a symbol.
        var emoji: String?
        var colorHex: String
        var type: String
        var isArchived: Bool
        var sortIndex: Int
        var createdAt: Date
    }

    struct RecurringRuleDTO: Codable {
        var id: UUID
        var title: String
        var amount: Decimal
        var type: String
        var frequency: String
        var interval: Int
        var startDate: Date
        var endDate: Date?
        var note: String
        var isActive: Bool
        var lastPostedIndex: Int
        var createdAt: Date
        var accountID: UUID?
        var categoryID: UUID?
    }

    struct TransactionDTO: Codable {
        var id: UUID
        var title: String
        var amount: Decimal
        var type: String
        var date: Date
        var note: String
        var createdAt: Date
        var updatedAt: Date
        var accountID: UUID?
        var categoryID: UUID?
        var recurringRuleID: UUID?
    }
}

struct BackupSummary {
    var accounts: Int
    var categories: Int
    var recurringRules: Int
    var transactions: Int
}

enum BackupError: LocalizedError {
    case unreadableFile
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "That file isn't a valid Expense Tracker backup."
        case .unsupportedVersion(let version):
            return "This backup was made by a newer version of the app (format \(version))."
        }
    }
}

enum BackupService {

    // MARK: - Export

    /// Snapshots the whole store — accounts, categories, rules and transactions —
    /// into a codable payload, stamped with the current currency and app version.
    /// - Parameter context: The context to read from.
    /// - Returns: The populated payload.
    /// - Throws: Any fetch error from the context.
    static func makePayload(from context: ModelContext) throws -> BackupPayload {
        var payload = BackupPayload()
        payload.currencyCode = Formatters.currencyCode
        payload.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        payload.accounts = try context.fetch(FetchDescriptor<Account>()).map { account in
            .init(
                id: account.id,
                name: account.name,
                kind: account.kindRaw,
                openingBalance: account.openingBalance,
                colorHex: account.colorHex,
                symbolName: account.symbolName,
                isArchived: account.isArchived,
                sortIndex: account.sortIndex,
                note: account.note,
                createdAt: account.createdAt
            )
        }

        payload.categories = try context.fetch(FetchDescriptor<Category>()).map { category in
            .init(
                id: category.id,
                name: category.name,
                symbolName: category.symbol,
                emoji: nil,
                colorHex: category.colorHex,
                type: category.typeRaw,
                isArchived: category.isArchived,
                sortIndex: category.sortIndex,
                createdAt: category.createdAt
            )
        }

        payload.recurringRules = try context.fetch(FetchDescriptor<RecurringRule>()).map { rule in
            .init(
                id: rule.id,
                title: rule.title,
                amount: rule.amount,
                type: rule.typeRaw,
                frequency: rule.frequencyRaw,
                interval: rule.interval,
                startDate: rule.startDate,
                endDate: rule.endDate,
                note: rule.note,
                isActive: rule.isActive,
                lastPostedIndex: rule.lastPostedIndex,
                createdAt: rule.createdAt,
                accountID: rule.account?.id,
                categoryID: rule.category?.id
            )
        }

        payload.transactions = try context.fetch(FetchDescriptor<Transaction>()).map { transaction in
            .init(
                id: transaction.id,
                title: transaction.title,
                amount: transaction.amount,
                type: transaction.typeRaw,
                date: transaction.date,
                note: transaction.note,
                createdAt: transaction.createdAt,
                updatedAt: transaction.updatedAt,
                accountID: transaction.account?.id,
                categoryID: transaction.category?.id,
                recurringRuleID: transaction.recurringRule?.id
            )
        }

        return payload
    }

    /// Encodes a payload as pretty-printed JSON with ISO-8601 dates and sorted
    /// keys, so two backups of the same data diff cleanly.
    /// - Parameter payload: The snapshot to encode.
    /// - Returns: The JSON data to write to disk.
    /// - Throws: Any `JSONEncoder` error.
    static func encode(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Reads a backup file, rejecting anything unparseable or written by a
    /// newer format version than this build understands.
    /// - Parameter data: Contents of the chosen file.
    /// - Returns: The decoded payload.
    /// - Throws: `BackupError.unreadableFile` or `.unsupportedVersion`.
    static func decode(_ data: Data) throws -> BackupPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(BackupPayload.self, from: data) else {
            throw BackupError.unreadableFile
        }
        guard payload.formatVersion <= BackupPayload.currentFormatVersion else {
            throw BackupError.unsupportedVersion(payload.formatVersion)
        }
        return payload
    }

    // MARK: - Restore

    /// Wipes the store and rebuilds it from `payload`. Destructive by design —
    /// the caller confirms with the user first.
    @discardableResult
    static func restore(_ payload: BackupPayload, into context: ModelContext) throws -> BackupSummary {
        try context.delete(model: Transaction.self)
        try context.delete(model: RecurringRule.self)
        try context.delete(model: Category.self)
        try context.delete(model: Account.self)
        try context.save()

        var accountsByID: [UUID: Account] = [:]
        for dto in payload.accounts {
            let account = Account(
                id: dto.id,
                name: dto.name,
                kind: AccountKind(rawValue: dto.kind) ?? .bank,
                openingBalance: dto.openingBalance,
                colorHex: dto.colorHex,
                symbolName: dto.symbolName,
                sortIndex: dto.sortIndex,
                note: dto.note,
                createdAt: dto.createdAt
            )
            account.isArchived = dto.isArchived
            context.insert(account)
            accountsByID[dto.id] = account
        }

        var categoriesByID: [UUID: Category] = [:]
        for dto in payload.categories {
            let category = Category(
                id: dto.id,
                name: dto.name,
                symbol: dto.symbolName,
                emoji: dto.emoji ?? "",
                colorHex: dto.colorHex,
                type: TransactionType(rawValue: dto.type) ?? .expense,
                sortIndex: dto.sortIndex,
                createdAt: dto.createdAt
            )
            category.isArchived = dto.isArchived
            context.insert(category)
            categoriesByID[dto.id] = category
        }

        var rulesByID: [UUID: RecurringRule] = [:]
        for dto in payload.recurringRules {
            let rule = RecurringRule(
                id: dto.id,
                title: dto.title,
                amount: dto.amount,
                type: TransactionType(rawValue: dto.type) ?? .expense,
                frequency: RecurrenceFrequency(rawValue: dto.frequency) ?? .monthly,
                interval: dto.interval,
                startDate: dto.startDate,
                endDate: dto.endDate,
                note: dto.note,
                account: dto.accountID.flatMap { accountsByID[$0] },
                category: dto.categoryID.flatMap { categoriesByID[$0] },
                createdAt: dto.createdAt
            )
            rule.isActive = dto.isActive
            rule.lastPostedIndex = dto.lastPostedIndex
            context.insert(rule)
            rulesByID[dto.id] = rule
        }

        for dto in payload.transactions {
            let transaction = Transaction(
                id: dto.id,
                title: dto.title,
                amount: dto.amount,
                type: TransactionType(rawValue: dto.type) ?? .expense,
                date: dto.date,
                note: dto.note,
                account: dto.accountID.flatMap { accountsByID[$0] },
                category: dto.categoryID.flatMap { categoriesByID[$0] },
                recurringRule: dto.recurringRuleID.flatMap { rulesByID[$0] },
                createdAt: dto.createdAt
            )
            transaction.updatedAt = dto.updatedAt
            context.insert(transaction)
        }

        try context.save()

        if !payload.currencyCode.isEmpty {
            UserDefaults.standard.set(payload.currencyCode, forKey: SettingsKey.currencyCode)
        }

        return BackupSummary(
            accounts: payload.accounts.count,
            categories: payload.categories.count,
            recurringRules: payload.recurringRules.count,
            transactions: payload.transactions.count
        )
    }

    /// Removes every record but keeps the default categories, for a clean slate.
    static func eraseAll(in context: ModelContext, reseed: Bool) throws {
        try context.delete(model: Transaction.self)
        try context.delete(model: RecurringRule.self)
        try context.delete(model: Category.self)
        try context.delete(model: Account.self)
        try context.save()
        if reseed {
            SeedData.seedIfNeeded(in: context)
        }
    }
}
