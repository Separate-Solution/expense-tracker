import Foundation
import SwiftData

/// Full-fidelity local backup: every account, category, rule and transaction in
/// one JSON file, with relationships stored as IDs so restore can rebuild them.
struct BackupPayload: Codable {
    /// 2 dropped the required `emoji` field from categories in favour of
    /// `symbolName`. Older builds require `emoji`, so the bump makes them
    /// report "made by a newer version" instead of failing to decode.
    ///
    /// 3 added credit cards, along with the card link and kind on transactions.
    /// Everything it adds is optional, so a version 2 backup still restores.
    ///
    /// 4 added the transfer destination on transactions. A version 3 build
    /// reading one would drop the destination and leave a transfer looking like
    /// a plain expense, so the bump makes it decline the file instead.
    ///
    /// 5 added EMI plans and the link from an instalment back to its plan.
    /// Everything it adds is optional, so a version 4 backup still restores.
    static let currentFormatVersion = 5

    var formatVersion: Int = BackupPayload.currentFormatVersion
    var exportedAt: Date = Date()
    var appVersion: String = ""
    var currencyCode: String = ""
    var accounts: [AccountDTO] = []
    /// Absent in backups written before credit cards existed.
    var creditCards: [CreditCardDTO]? = []
    var categories: [CategoryDTO] = []
    var recurringRules: [RecurringRuleDTO] = []
    /// Absent in backups written before EMIs existed.
    var emiPlans: [EMIPlanDTO]? = []
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

    struct CreditCardDTO: Codable {
        var id: UUID
        var name: String
        var creditLimit: Decimal
        var statementDay: Int
        var dueDay: Int
        var openingOutstanding: Decimal
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
        /// Absent in backups written before credit cards existed.
        var creditCardID: UUID?
        var categoryID: UUID?
    }

    struct EMIPlanDTO: Codable {
        var id: UUID
        var title: String
        var principal: Decimal
        var annualInterestRate: Decimal
        var foreclosureChargePercent: Decimal
        var frequency: String
        var interval: Int
        var installmentCount: Int
        var installmentAmount: Decimal
        var startDate: Date
        var status: String
        var lastPostedIndex: Int
        /// Instalments already paid when the plan was added; absent on backups
        /// written before that was tracked.
        var skippedInstallmentCount: Int?
        var closedDate: Date?
        var closingPaymentID: UUID?
        var note: String
        var createdAt: Date
        var accountID: UUID?
        var creditCardID: UUID?
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
        /// Absent in backups written before credit cards existed; "standard" then.
        var kind: String?
        var accountID: UUID?
        /// Absent in backups written before credit cards existed.
        var creditCardID: UUID?
        /// The far side of a transfer; absent before transfers existed.
        var toAccountID: UUID?
        var categoryID: UUID?
        var recurringRuleID: UUID?
        /// The EMI plan an instalment belongs to; absent before EMIs existed.
        var emiPlanID: UUID?
        /// Which instalment of that plan it is; absent on the payment that
        /// foreclosed one, and on rows written before EMIs existed.
        var emiInstallmentIndex: Int?
    }
}

struct BackupSummary {
    var accounts: Int
    var creditCards: Int
    var categories: Int
    var recurringRules: Int
    var emiPlans: Int
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

        payload.creditCards = try context.fetch(FetchDescriptor<CreditCard>()).map { card in
            .init(
                id: card.id,
                name: card.name,
                creditLimit: card.creditLimit,
                statementDay: card.statementDay,
                dueDay: card.dueDay,
                openingOutstanding: card.openingOutstanding,
                colorHex: card.colorHex,
                symbolName: card.symbolName,
                isArchived: card.isArchived,
                sortIndex: card.sortIndex,
                note: card.note,
                createdAt: card.createdAt
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
                creditCardID: rule.creditCard?.id,
                categoryID: rule.category?.id
            )
        }

        payload.emiPlans = try context.fetch(FetchDescriptor<EMIPlan>()).map { plan in
            .init(
                id: plan.id,
                title: plan.title,
                principal: plan.principal,
                annualInterestRate: plan.annualInterestRate,
                foreclosureChargePercent: plan.foreclosureChargePercent,
                frequency: plan.frequencyRaw,
                interval: plan.interval,
                installmentCount: plan.installmentCount,
                installmentAmount: plan.installmentAmount,
                startDate: plan.startDate,
                status: plan.statusRaw,
                lastPostedIndex: plan.lastPostedIndex,
                skippedInstallmentCount: plan.skippedInstallmentCount,
                closedDate: plan.closedDate,
                closingPaymentID: plan.closingPaymentID,
                note: plan.note,
                createdAt: plan.createdAt,
                accountID: plan.account?.id,
                creditCardID: plan.creditCard?.id,
                categoryID: plan.category?.id
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
                kind: transaction.kindRaw,
                accountID: transaction.account?.id,
                creditCardID: transaction.creditCard?.id,
                toAccountID: transaction.toAccount?.id,
                categoryID: transaction.category?.id,
                recurringRuleID: transaction.recurringRule?.id,
                emiPlanID: transaction.emiPlan?.id,
                emiInstallmentIndex: transaction.emiInstallmentIndex
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
    @MainActor
    static func restore(
        _ payload: BackupPayload,
        into context: ModelContext,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> BackupSummary {
        // Weighted by row count so the bar tracks the work rather than the
        // number of phases — a file is mostly transactions.
        let cardCount = (payload.creditCards ?? []).count
        let planCount = (payload.emiPlans ?? []).count
        let total = payload.accounts.count + cardCount + payload.categories.count
            + payload.recurringRules.count + planCount + payload.transactions.count
        var done = 0
        let ticker = onProgress.map { ProgressTicker(total: max(1, total), report: $0) }

        /// Counts one restored row and lets the overlay redraw on the stride.
        func step() async {
            done += 1
            if ticker?.tick(completed: done) == true {
                await Task.yield()
            }
        }

        // Budgets are cleared with everything else even though a backup carries
        // none of its own — restoring replaces all current data, and leaving
        // them would attach the old ones to whatever came in.
        try await deleteAllRecords(in: context)
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
            await step()
        }

        var cardsByID: [UUID: CreditCard] = [:]
        for dto in payload.creditCards ?? [] {
            let card = CreditCard(
                id: dto.id,
                name: dto.name,
                creditLimit: dto.creditLimit,
                statementDay: dto.statementDay,
                dueDay: dto.dueDay,
                openingOutstanding: dto.openingOutstanding,
                colorHex: dto.colorHex,
                symbolName: dto.symbolName,
                sortIndex: dto.sortIndex,
                note: dto.note,
                createdAt: dto.createdAt
            )
            card.isArchived = dto.isArchived
            context.insert(card)
            cardsByID[dto.id] = card
            await step()
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
            await step()
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
                creditCard: dto.creditCardID.flatMap { cardsByID[$0] },
                category: dto.categoryID.flatMap { categoriesByID[$0] },
                createdAt: dto.createdAt
            )
            rule.isActive = dto.isActive
            rule.lastPostedIndex = dto.lastPostedIndex
            context.insert(rule)
            rulesByID[dto.id] = rule
            await step()
        }

        var plansByID: [UUID: EMIPlan] = [:]
        for dto in payload.emiPlans ?? [] {
            let plan = EMIPlan(
                id: dto.id,
                title: dto.title,
                principal: dto.principal,
                annualInterestRate: dto.annualInterestRate,
                foreclosureChargePercent: dto.foreclosureChargePercent,
                frequency: RecurrenceFrequency(rawValue: dto.frequency) ?? .monthly,
                interval: dto.interval,
                installmentCount: dto.installmentCount,
                installmentAmount: dto.installmentAmount,
                startDate: dto.startDate,
                note: dto.note,
                account: dto.accountID.flatMap { accountsByID[$0] },
                creditCard: dto.creditCardID.flatMap { cardsByID[$0] },
                category: dto.categoryID.flatMap { categoriesByID[$0] },
                createdAt: dto.createdAt
            )
            plan.status = EMIStatus(rawValue: dto.status) ?? .active
            plan.lastPostedIndex = dto.lastPostedIndex
            plan.skippedInstallmentCount = dto.skippedInstallmentCount ?? 0
            plan.closedDate = dto.closedDate
            plan.closingPaymentID = dto.closingPaymentID
            context.insert(plan)
            plansByID[dto.id] = plan
            await step()
        }

        for dto in payload.transactions {
            let transaction = Transaction(
                id: dto.id,
                title: dto.title,
                amount: dto.amount,
                type: TransactionType(rawValue: dto.type) ?? .expense,
                date: dto.date,
                note: dto.note,
                kind: dto.kind.flatMap { TransactionKind(rawValue: $0) } ?? .standard,
                account: dto.accountID.flatMap { accountsByID[$0] },
                creditCard: dto.creditCardID.flatMap { cardsByID[$0] },
                toAccount: dto.toAccountID.flatMap { accountsByID[$0] },
                category: dto.categoryID.flatMap { categoriesByID[$0] },
                recurringRule: dto.recurringRuleID.flatMap { rulesByID[$0] },
                emiPlan: dto.emiPlanID.flatMap { plansByID[$0] },
                emiInstallmentIndex: dto.emiInstallmentIndex,
                createdAt: dto.createdAt
            )
            transaction.updatedAt = dto.updatedAt
            // The file is the one input nothing in the app validated on the way
            // in, so the movement invariants are enforced here rather than
            // trusted.
            transaction.normaliseMovement()
            context.insert(transaction)
            await step()
        }

        // A version 1 or 2 backup can carry accounts saved under the retired
        // `.credit` kind. Migrating here rather than waiting for the next launch
        // keeps the restored store consistent with what the app just showed.
        SeedData.migrateLegacyCreditAccounts(in: context)

        try context.save()

        if !payload.currencyCode.isEmpty {
            UserDefaults.standard.set(payload.currencyCode, forKey: SettingsKey.currencyCode)
        }
        onProgress?(1)

        // Counted from the store rather than the file: migrating a legacy credit
        // account turns it into a card, so the file's own tallies would report
        // an account that is no longer there and miss the card that replaced it.
        return BackupSummary(
            accounts: (try? context.fetchCount(FetchDescriptor<Account>())) ?? payload.accounts.count,
            creditCards: (try? context.fetchCount(FetchDescriptor<CreditCard>()))
                ?? (payload.creditCards ?? []).count,
            categories: (try? context.fetchCount(FetchDescriptor<Category>())) ?? payload.categories.count,
            recurringRules: (try? context.fetchCount(FetchDescriptor<RecurringRule>()))
                ?? payload.recurringRules.count,
            emiPlans: (try? context.fetchCount(FetchDescriptor<EMIPlan>()))
                ?? (payload.emiPlans ?? []).count,
            transactions: (try? context.fetchCount(FetchDescriptor<Transaction>()))
                ?? payload.transactions.count
        )
    }

    // MARK: - Wiping

    /// Every model in the store, in the order a wipe has to clear them: rows
    /// before the things they point at.
    ///
    /// One list, because both paths that empty the store — erasing and
    /// restoring — need exactly the same one. They each had their own before,
    /// and budgets were added to the schema without reaching either, so they
    /// outlived a wipe that said everything was gone. A model added to the
    /// schema belongs here too.
    private static let wipeSteps: [(ModelContext) throws -> Void] = [
        { try $0.delete(model: Transaction.self) },
        { try $0.delete(model: RecurringRule.self) },
        { try $0.delete(model: EMIPlan.self) },
        { try $0.delete(model: Budget.self) },
        { try $0.delete(model: Category.self) },
        { try $0.delete(model: CreditCard.self) },
        { try $0.delete(model: Account.self) }
    ]

    /// How many steps a wipe runs through, for pacing a progress bar.
    static var wipeStepCount: Int { wipeSteps.count }

    /// Deletes every record in the store, leaving the changes unsaved so the
    /// caller can save once, alongside whatever it does next.
    /// - Parameters:
    ///   - context: The store to empty.
    ///   - onStepComplete: Called after each model is cleared.
    /// - Throws: Any delete error from the context.
    @MainActor
    static func deleteAllRecords(
        in context: ModelContext,
        onStepComplete: () async -> Void = {}
    ) async throws {
        for step in wipeSteps {
            try step(context)
            await onStepComplete()
        }
    }

    /// Removes every record but keeps the default categories, for a clean slate.
    /// - Parameters:
    ///   - context: The store to wipe.
    ///   - reseed: Whether to put the default categories back.
    ///   - onProgress: Called with the fraction done, 0...1.
    @MainActor
    static func eraseAll(
        in context: ModelContext,
        reseed: Bool,
        onProgress: ((Double) -> Void)? = nil
    ) async throws {
        // Nothing here is per-row, so the bar tracks the steps of the wipe
        // instead, plus the save and the reseed.
        let steps = Double(wipeStepCount + (reseed ? 2 : 1))
        var done = 0.0

        try await deleteAllRecords(in: context) {
            done += 1
            onProgress?(done / steps)
            await Task.yield()
        }

        try context.save()
        done += 1
        onProgress?(done / steps)
        await Task.yield()

        if reseed {
            SeedData.seedIfNeeded(in: context)
            onProgress?(1)
        }
    }
}
