import Foundation
import SwiftData

struct CSVImportSummary {
    var imported: Int = 0
    var skippedDuplicates: Int = 0
    var createdAccounts: [String] = []
    var createdCreditCards: [String] = []
    var createdCategories: [String] = []
    var failures: [String] = []
    var ignoredColumns: [String] = []

    var isEmpty: Bool { imported == 0 && skippedDuplicates == 0 && failures.isEmpty }
}

enum CSVError: LocalizedError {
    case emptyFile
    case missingRequiredColumns([String])

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "That file has no rows in it."
        case .missingRequiredColumns(let columns):
            return "The file is missing required column(s): \(columns.joined(separator: ", "))."
        }
    }
}

/// A transaction field that can be read from a CSV column.
enum CSVField: String, CaseIterable, Identifiable {
    case date, time, amount, type, title, category, account, accountKind, creditCard
    case transferTo, note, id
    case income, color, icon, emoji

    var id: String { rawValue }

    /// Fields offered on the mapping screen, in the order they're shown.
    static let assignable: [CSVField] = [
        .date, .time, .amount, .type, .title, .category,
        .account, .accountKind, .creditCard, .transferTo, .note, .id
    ]

    var label: String {
        switch self {
        case .date: return "Date"
        case .time: return "Time"
        case .amount: return "Amount"
        case .type: return "Type"
        case .title: return "Title"
        case .category: return "Category"
        case .account: return "Account"
        case .accountKind: return "Account Type"
        case .creditCard: return "Credit Card"
        case .transferTo: return "Transfer To"
        case .note: return "Note"
        case .id: return "ID"
        case .income: return "Income flag"
        case .color: return "Category colour"
        case .icon: return "Category icon"
        case .emoji: return "Category emoji"
        }
    }

    var isRequired: Bool { self == .date || self == .amount }

    /// What happens when this column is left unassigned. Shown under every
    /// unassigned row so a blank picker is never a silent surprise.
    var unassignedNote: String {
        switch self {
        case .date: return "Required. Nothing can be imported without it."
        case .time: return "Transactions come in at the start of the day, unless the date column carries a time."
        case .amount: return "Required. Nothing can be imported without it."
        case .type: return "Falls back to the sign of the amount — negative becomes an expense."
        case .title: return "Falls back to the category name."
        case .category: return "Transactions come in without a category."
        case .account: return "Everything goes into your first account."
        case .accountKind: return "Guessed from the account name."
        case .creditCard: return "Nothing is charged to a credit card."
        case .transferTo: return "No row is treated as a transfer between accounts."
        case .note: return "Notes are left empty."
        case .id: return "Duplicates can't be detected, so importing this file twice adds it twice."
        default: return ""
        }
    }

    /// Header names matched automatically, compared after normalising away
    /// case, spaces and punctuation.
    var aliases: [String] {
        switch self {
        case .date: return ["date", "transactiondate", "day"]
        case .time: return ["time", "transactiontime", "timeofday", "clock"]
        case .amount: return ["amount", "value", "sum"]
        case .type: return ["type", "transactiontype", "kind", "direction", "drcr", "crdr"]
        case .title: return ["title", "name", "description", "notetitle", "payee", "merchant", "narration", "particulars"]
        case .category: return ["category", "categoryname"]
        case .account: return ["account", "accountname", "bank", "source"]
        case .accountKind: return ["accounttype", "accountkind"]
        case .creditCard: return ["creditcard", "card", "cardname", "creditcardname"]
        case .transferTo: return ["transferto", "toaccount", "destination", "transferaccount"]
        case .note: return ["note", "notes", "memo", "comment"]
        case .id: return ["id", "uuid", "transactionid"]
        case .income: return ["income", "isincome"]
        case .color: return ["color", "categorycolor"]
        case .icon: return ["icon", "categoryicon"]
        case .emoji: return ["emoji", "categoryemoji"]
        }
    }
}

/// Which CSV column each field reads from, plus the date pattern to read with.
struct CSVColumnMapping {
    var indices: [CSVField: Int] = [:]
    var datePattern: String?

    var missingRequiredFields: [CSVField] {
        CSVField.assignable.filter { $0.isRequired && indices[$0] == nil }
    }

    /// Column indices in use, so anything left over can be reported as ignored.
    var usedIndices: Set<Int> { Set(indices.values) }
}

/// A parsed file waiting to be imported. Holds no database state — building one
/// is safe and reversible, which is what lets the mapping be reviewed first.
struct CSVImportPlan: Identifiable {
    let id = UUID()
    let headers: [String]
    let rows: [[String]]
    let suggestedMapping: CSVColumnMapping

    /// A copy of this plan carrying a different mapping.
    /// - Parameter mapping: The mapping to substitute.
    /// - Returns: A new plan over the same rows.
    func replacingSuggestedMapping(with mapping: CSVColumnMapping) -> CSVImportPlan {
        CSVImportPlan(headers: headers, rows: rows, suggestedMapping: mapping)
    }

    var transactionCount: Int { rows.count }

    /// Every non-empty value in `column`. Used to work out the date format, and
    /// recomputed when the Date assignment changes: a column we didn't detect
    /// automatically has never been sampled.
    func values(inColumn index: Int?) -> [String] {
        guard let index else { return [] }
        return rows.compactMap { row in
            guard index < row.count else { return nil }
            let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
    }

    /// Date patterns that parse every value in `index`.
    /// - Parameter index: Column to sample; nil yields no formats.
    /// - Returns: Matching patterns, most specific first.
    func dateFormats(inColumn index: Int?) -> [String] {
        CSVService.detectDateFormats(in: values(inColumn: index))
    }

    var firstRow: [String] { rows.first ?? [] }

    /// The trimmed sample value shown as a preview for a column.
    /// - Parameter index: Column to read.
    /// - Returns: The value, or "" when the row is short.
    func value(inFirstRow index: Int) -> String {
        index < firstRow.count ? firstRow[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// Header names that no field reads from — the columns that would otherwise
    /// be dropped without telling anyone.
    func ignoredColumns(for mapping: CSVColumnMapping) -> [String] {
        let used = mapping.usedIndices
        return headers.enumerated()
            .filter { !used.contains($0.offset) && !$0.element.isEmpty }
            .map(\.element)
    }
}

enum CSVService {

    static let exportHeader = [
        "Date", "Time", "Title", "Type", "Amount", "Currency",
        "Account", "Account Type", "Credit Card", "Transfer To", "Category", "Note", "ID"
    ]

    // MARK: - Export

    /// Renders transactions as CSV using `exportHeader`, oldest first.
    /// - Parameter transactions: The rows to export.
    /// - Returns: The complete CSV text.
    static func exportString(transactions: [Transaction]) -> String {
        var rows = [exportHeader.map(escape).joined(separator: ",")]
        let sorted = transactions.sorted { $0.date < $1.date }
        for transaction in sorted {
            let fields = [
                isoDateFormatter.string(from: transaction.date),
                isoTimeFormatter.string(from: transaction.date),
                transaction.title,
                transaction.type.title,
                NSDecimalNumber(decimal: transaction.amount.roundedToCurrency)
                    .description(withLocale: Locale(identifier: "en_US_POSIX")),
                Formatters.currencyCode,
                transaction.account?.name ?? "",
                transaction.account?.kind.rawValue ?? "",
                transaction.creditCard?.name ?? "",
                transaction.toAccount?.name ?? "",
                transaction.category?.name ?? "",
                transaction.note,
                transaction.id.uuidString
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    // MARK: - Import

    /// Parses `text`, then imports it using the automatically suggested mapping.
    /// Kept for callers that don't show the mapping screen; the UI path uses
    /// `prepare` + `commit` so the user can correct a bad guess first.
    static func importTransactions(
        from text: String,
        into context: ModelContext,
        defaultAccount: Account?
    ) throws -> CSVImportSummary {
        let plan = try prepare(from: text)
        let missing = plan.suggestedMapping.missingRequiredFields
        guard missing.isEmpty else {
            throw CSVError.missingRequiredColumns(missing.map(\.label))
        }
        return try commit(plan, mapping: plan.suggestedMapping, into: context, defaultAccount: defaultAccount)
    }

    /// Reads the file and works out a proposed column mapping without touching
    /// the database, so the mapping can be reviewed before anything is written.
    static func prepare(from text: String) throws -> CSVImportPlan {
        let rows = parse(text)
        guard let headerRow = rows.first, rows.count > 1 else { throw CSVError.emptyFile }

        let dataRows = Array(rows.dropFirst()).filter { row in
            !row.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !dataRows.isEmpty else { throw CSVError.emptyFile }

        let normalized = headerRow.map(normalizeKey)
        var indices: [CSVField: Int] = [:]
        for field in CSVField.allCases {
            for alias in field.aliases {
                if let index = normalized.firstIndex(of: alias) {
                    indices[field] = index
                    break
                }
            }
        }

        let plan = CSVImportPlan(
            headers: headerRow.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            rows: dataRows,
            suggestedMapping: CSVColumnMapping(indices: indices)
        )

        // Look at every date in the file, not just the first row: a value like
        // 15/03 rules out MM/dd/yyyy, which is what makes an ambiguous file
        // resolvable instead of a coin flip.
        var suggested = plan.suggestedMapping
        suggested.datePattern = plan.dateFormats(inColumn: indices[.date]).first
        return plan.replacingSuggestedMapping(with: suggested)
    }

    /// Date patterns that parse every sample given, in priority order. More than
    /// one means the file is genuinely ambiguous and the user has to choose.
    static func detectDateFormats(in samples: [String]) -> [String] {
        guard !samples.isEmpty else { return [] }
        let checked = samples.prefix(200)
        return datePatterns.filter { pattern in
            checked.allSatisfy { strictlyMatches($0, pattern: pattern) }
        }
    }

    /// DateFormatter is lenient about separators — "dd-MM-yyyy" happily reads
    /// "03/04/2026" — which would fill the format picker with choices that
    /// differ only cosmetically. Re-formatting the parsed date and comparing the
    /// punctuation back to the input rejects those, while still allowing
    /// unpadded values like "3/4/2026".
    private static func strictlyMatches(_ sample: String, pattern: String) -> Bool {
        let formatter = formatter(for: pattern)
        guard let date = formatter.date(from: sample) else { return false }
        return punctuation(of: formatter.string(from: date)) == punctuation(of: sample)
    }

    /// The separators in `text` with letters, digits and spaces stripped,
    /// used to compare a re-formatted date against the original input.
    private static func punctuation(of text: String) -> String {
        String(text.filter { !$0.isLetter && !$0.isNumber && !$0.isWhitespace })
    }

    /// Inserts transactions using an explicit mapping, creating any account or
    /// category named in the file that does not exist yet. Rows whose ID already
    /// exists are skipped so re-importing the same export is safe.
    static func commit(
        _ plan: CSVImportPlan,
        mapping: CSVColumnMapping,
        into context: ModelContext,
        defaultAccount: Account?
    ) throws -> CSVImportSummary {
        let missing = mapping.missingRequiredFields
        guard missing.isEmpty else {
            throw CSVError.missingRequiredColumns(missing.map(\.label))
        }

        var summary = CSVImportSummary()
        summary.ignoredColumns = plan.ignoredColumns(for: mapping)

        var accountCache = try existingAccountsByName(in: context)
        var cardCache = try existingCreditCardsByName(in: context)
        var categoryCache = try existingCategoriesByKey(in: context)
        var seenIDs = try existingTransactionIDs(in: context)

        for (offset, row) in plan.rows.enumerated() {
            let lineNumber = offset + 2
            /// Reads this row's value for a mapped field, or "" when the column
            /// is unmapped or the row is short.
            func field(_ csvField: CSVField) -> String {
                guard let index = mapping.indices[csvField], index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            guard let parsedDate = parseDate(field(.date), using: mapping.datePattern) else {
                summary.failures.append("Line \(lineNumber): couldn't read the date “\(field(.date))”.")
                continue
            }
            // A separate time column wins over any time the date column carried;
            // an empty or unreadable one leaves the date's own time alone rather
            // than failing the row.
            let date = applyingTimeOfDay(field(.time), to: parsedDate)
            guard let signedAmount = parseAmount(field(.amount)) else {
                summary.failures.append("Line \(lineNumber): couldn't read the amount “\(field(.amount))”.")
                continue
            }

            // A boolean "income" column is the most reliable signal (Cashew writes one),
            // then an explicit type word, then finally the sign of the amount.
            let type: TransactionType
            if let isIncome = parseBool(field(.income)) {
                type = isIncome ? .income : .expense
            } else if let explicit = parseType(field(.type)) {
                type = explicit
            } else {
                type = signedAmount < 0 ? .expense : .income
            }

            let existingID = UUID(uuidString: field(.id))
            if let existingID {
                if seenIDs.contains(existingID) {
                    summary.skippedDuplicates += 1
                    continue
                }
                seenIDs.insert(existingID)
            }

            let accountName = field(.account)
            let explicitCardName = field(.creditCard)
            let declaredKind = AccountKind(rawValue: field(.accountKind).lowercased())

            // An export from before cards had their own model put the card's
            // name in the Account column with Account Type "credit", and had no
            // Credit Card column at all. Such a row is the card itself, not a
            // bank account, so it comes in as one rather than being flattened
            // to a bank account the migration would never look at again.
            let isLegacyCreditRow = explicitCardName.isEmpty
                && !accountName.isEmpty
                && declaredKind?.isLegacyCreditKind == true
            let cardName = isLegacyCreditRow ? accountName : explicitCardName

            var creditCard: CreditCard?
            if !cardName.isEmpty {
                let key = cardName.lowercased()
                if let existing = cardCache[key] {
                    creditCard = existing
                } else {
                    // The file can't carry a limit or a billing cycle, so the
                    // card comes in with the defaults and the cards list flags
                    // it as needing a limit.
                    let created = CreditCard(
                        name: cardName,
                        colorHex: Theme.paletteHexes[cardCache.count % Theme.paletteHexes.count],
                        sortIndex: cardCache.count
                    )
                    context.insert(created)
                    cardCache[key] = created
                    creditCard = created
                    summary.createdCreditCards.append(cardName)
                }
            }

            // A row naming both is a bill payment — the export writes the card
            // and the bank account it was paid from on the same line. A row
            // naming only a card was charged to it, so no account is involved.
            var account: Account? = creditCard == nil ? defaultAccount : nil
            if !accountName.isEmpty, !isLegacyCreditRow {
                let key = accountName.lowercased()
                if let existing = accountCache[key] {
                    account = existing
                } else {
                    // `credit` is retired, so a file still carrying it falls back
                    // to a guess from the name; a legacy credit row never reaches
                    // here, having already become a card above.
                    let kind = (declaredKind?.isLegacyCreditKind ?? true)
                        ? inferAccountKind(from: accountName)
                        : (declaredKind ?? .bank)
                    let created = Account(
                        name: accountName,
                        kind: kind,
                        colorHex: Theme.paletteHexes[accountCache.count % Theme.paletteHexes.count],
                        sortIndex: accountCache.count
                    )
                    context.insert(created)
                    accountCache[key] = created
                    account = created
                    summary.createdAccounts.append(accountName)
                }
            }

            // A destination account makes the row a transfer out of `account`.
            let transferToName = field(.transferTo)
            var toAccount: Account?
            if !transferToName.isEmpty, transferToName.lowercased() != accountName.lowercased() {
                let key = transferToName.lowercased()
                if let existing = accountCache[key] {
                    toAccount = existing
                } else {
                    let created = Account(
                        name: transferToName,
                        kind: inferAccountKind(from: transferToName),
                        colorHex: Theme.paletteHexes[accountCache.count % Theme.paletteHexes.count],
                        sortIndex: accountCache.count
                    )
                    context.insert(created)
                    accountCache[key] = created
                    toAccount = created
                    summary.createdAccounts.append(transferToName)
                }
            }

            // Compared as resolved accounts, not as column text: a blank
            // Account column falls back to the default account, which the
            // destination may well name, and "Checking" != "" would have made
            // that a transfer to itself.
            if let resolvedTo = toAccount, resolvedTo.id == account?.id {
                toAccount = nil
            }

            let kind: TransactionKind
            if toAccount != nil, account != nil {
                kind = .transfer
            } else if creditCard != nil, account != nil {
                kind = .cardPayment
            } else {
                kind = .standard
            }
            // A destination with nothing to leave from isn't a transfer.
            if kind != .transfer { toAccount = nil }

            let categoryName = field(.category)
            var category: Category?
            if !categoryName.isEmpty {
                let key = "\(type.rawValue)|\(categoryName.lowercased())"
                if let existing = categoryCache[key] {
                    category = existing
                } else {
                    let created = Category(
                        name: categoryName,
                        symbol: categorySymbol(
                            name: categoryName,
                            explicit: field(.emoji),
                            iconName: field(.icon),
                            type: type
                        ),
                        colorHex: parseColorHex(field(.color))
                            ?? Theme.paletteHexes[categoryCache.count % Theme.paletteHexes.count],
                        type: type,
                        sortIndex: categoryCache.count
                    )
                    context.insert(created)
                    categoryCache[key] = created
                    category = created
                    summary.createdCategories.append(categoryName)
                }
            }

            let title = field(.title).isEmpty
                ? (category?.name ?? "Imported transaction")
                : field(.title)

            let transaction = Transaction(
                id: existingID ?? UUID(),
                title: title,
                amount: abs(signedAmount).roundedToCurrency,
                // A movement always leaves its source; the other end picks it
                // up. A file claiming income would credit both sides at once.
                type: kind.isMovement ? .expense : type,
                date: date,
                note: field(.note),
                kind: kind,
                account: account,
                creditCard: creditCard,
                toAccount: toAccount,
                category: category
            )
            context.insert(transaction)
            summary.imported += 1
        }

        try context.save()
        return summary
    }

    // MARK: - Lookups

    /// Accounts keyed by lowercased name, so an imported name reuses an
    /// existing account instead of creating a near-duplicate.
    private static func existingAccountsByName(in context: ModelContext) throws -> [String: Account] {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        return Dictionary(accounts.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Credit cards keyed by lowercased name, so an imported name reuses an
    /// existing card instead of creating a near-duplicate.
    private static func existingCreditCardsByName(in context: ModelContext) throws -> [String: CreditCard] {
        let cards = try context.fetch(FetchDescriptor<CreditCard>())
        return Dictionary(cards.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Categories keyed by type and lowercased name — the same name can exist
    /// once for expenses and once for income.
    private static func existingCategoriesByKey(in context: ModelContext) throws -> [String: Category] {
        let categories = try context.fetch(FetchDescriptor<Category>())
        return Dictionary(
            categories.map { ("\($0.type.rawValue)|\($0.name.lowercased())", $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// IDs already in the store, used to skip rows from a re-imported export.
    private static func existingTransactionIDs(in context: ModelContext) throws -> Set<UUID> {
        Set(try context.fetch(FetchDescriptor<Transaction>()).map(\.id))
    }

    // MARK: - Field parsing

    /// Reads the spellings of true/false that turn up in exported files.
    /// - Parameter text: The cell value.
    /// - Returns: The boolean, or nil when unrecognised.
    static func parseBool(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "true", "yes", "y", "1": return true
        case "false", "no", "n", "0": return false
        default: return nil
        }
    }

    /// Accepts Flutter/Cashew style "0XFF4CAF50" (alpha first) as well as plain
    /// "RRGGBB" and "#RRGGBB". Returns the six-digit RGB portion.
    static func parseColorHex(_ text: String) -> String? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleaned.hasPrefix("0X") { cleaned = String(cleaned.dropFirst(2)) }
        if cleaned.hasPrefix("#") { cleaned = String(cleaned.dropFirst()) }
        guard cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
        if cleaned.count == 8 { cleaned = String(cleaned.dropFirst(2)) }  // drop alpha
        return cleaned.count == 6 ? cleaned : nil
    }

    /// Picks a category icon: the symbol matching an explicit emoji column if
    /// the file has one, else a known third-party icon name, else one inferred
    /// from the category's own name.
    /// - Parameters:
    ///   - name: The category name from the file.
    ///   - explicit: Value of the emoji column.
    ///   - iconName: Value of the icon-name column.
    ///   - type: Used to choose the fallback symbol.
    /// - Returns: An SF Symbol name.
    static func categorySymbol(
        name: String,
        explicit: String,
        iconName: String,
        type: TransactionType
    ) -> String {
        // No emoji-presentation check first: text-presentation glyphs like "✈"
        // are mapped too, and an unrecognised value already comes back nil.
        let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        if let mapped = CategoryIcon.symbol(forEmoji: trimmed) { return mapped }
        if let first = trimmed.first,
           let mapped = CategoryIcon.symbol(forEmoji: String(first)) {
            return mapped
        }
        if let mapped = CategoryIcon.symbol(forImportedIconName: iconName) { return mapped }
        return CategoryIcon.inferred(name: name, type: type)
    }

    /// Maps bank-statement wording (debit/credit, in/out) to a transaction type.
    /// - Parameter text: The cell value.
    /// - Returns: The type, or nil when unrecognised.
    static func parseType(_ text: String) -> TransactionType? {
        switch text.lowercased() {
        case "expense", "debit", "dr", "spend", "spending", "out", "withdrawal":
            return .expense
        case "income", "credit", "cr", "earning", "in", "deposit":
            return .income
        default:
            return nil
        }
    }

    /// Handles "1,234.56", "₹1,234", "(45.00)" and a leading minus sign.
    static func parseAmount(_ text: String) -> Decimal? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        var isNegative = false
        if cleaned.hasPrefix("(") && cleaned.hasSuffix(")") {
            isNegative = true
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        if cleaned.hasPrefix("-") || cleaned.hasPrefix("−") {
            isNegative = true
            cleaned = String(cleaned.dropFirst())
        }
        if cleaned.hasPrefix("+") { cleaned = String(cleaned.dropFirst()) }

        cleaned = cleaned.filter { $0.isNumber || $0 == "." || $0 == "," }
        // Treat commas as thousands separators; a trailing ",00" style decimal is
        // converted when there is no dot at all.
        if !cleaned.contains("."), cleaned.filter({ $0 == "," }).count == 1,
           let commaIndex = cleaned.firstIndex(of: ","),
           cleaned.distance(from: cleaned.index(after: commaIndex), to: cleaned.endIndex) == 2 {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        } else {
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        }

        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return isNegative ? -value : value
    }

    /// With an explicit `pattern`, only that pattern (and ISO 8601) is accepted:
    /// falling back to the general list would quietly undo the format the user
    /// picked on an ambiguous file. Without one, every known pattern is tried.
    static func parseDate(_ text: String, using pattern: String? = nil) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let pattern {
            if let date = formatter(for: pattern).date(from: trimmed) { return date }
            return ISO8601DateFormatter().date(from: trimmed)
        }
        for formatter in dateFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    /// Reads a time of day written on its own, in 24-hour or 12-hour form —
    /// "18:04", "18:04:22", "6:04 PM". Case is normalised first so a lowercase
    /// "pm" reads under the POSIX locale.
    /// - Parameter text: The raw column value.
    /// - Returns: Hour, minute and second, or nil when there is nothing to read.
    static func parseTime(_ text: String) -> DateComponents? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return nil }
        for pattern in timePatterns {
            guard let parsed = formatter(for: pattern).date(from: trimmed) else { continue }
            return Calendar.current.dateComponents([.hour, .minute, .second], from: parsed)
        }
        return nil
    }

    /// Moves `date` to the time of day written in `text`, keeping the day it
    /// already has. An empty or unreadable time leaves the date untouched.
    /// - Parameters:
    ///   - text: The raw time column value.
    ///   - date: The date parsed from the date column.
    /// - Returns: The combined date, or `date` when there is no time to apply.
    static func applyingTimeOfDay(_ text: String, to date: Date) -> Date {
        guard let time = parseTime(text),
              let hour = time.hour, let minute = time.minute else { return date }
        return Calendar.current.date(
            bySettingHour: hour, minute: minute, second: time.second ?? 0, of: date
        ) ?? date
    }

    /// Guesses an account kind from its name when the file does not say —
    /// "wallet" reads as cash, everything else a bank account. Card-sounding
    /// names are no longer guessed at: credit cards come in through the
    /// dedicated "Credit Card" column instead.
    /// - Parameter name: The account name from the file.
    /// - Returns: The inferred kind.
    private static func inferAccountKind(from name: String) -> AccountKind {
        let lowered = name.lowercased()
        if lowered.contains("cash") || lowered.contains("wallet") { return .cash }
        return .bank
    }

    // MARK: - Formatters

    static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let isoTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Patterns tried in order when no format has been chosen, most specific
    /// first. `dd/MM/yyyy` deliberately precedes `MM/dd/yyyy`; when a file
    /// matches both, the mapping screen asks instead of guessing.
    static let datePatterns = [
        "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd",
        "dd-MM-yyyy HH:mm:ss", "dd/MM/yyyy HH:mm:ss",
        "dd-MM-yyyy", "dd/MM/yyyy", "MM/dd/yyyy",
        "dd MMM yyyy", "MMM dd, yyyy", "dd-MMM-yyyy"
    ]

    /// Patterns tried against a standalone time column. The 12-hour ones come
    /// first: `DateFormatter` matches a prefix, so "HH:mm" would read "6:04 PM"
    /// as 06:04 and quietly drop the afternoon.
    static let timePatterns = [
        "h:mm:ss a", "h:mm a", "h a",
        "HH:mm:ss.SSS", "HH:mm:ss", "HH:mm"
    ]

    private static let formatterCache: [String: DateFormatter] = {
        var cache: [String: DateFormatter] = [:]
        for pattern in datePatterns + timePatterns { cache[pattern] = makeDateFormatter(pattern) }
        return cache
    }()

    /// Builds a POSIX-locale formatter for `pattern`, so parsing never shifts
    /// with the device's region settings.
    private static func makeDateFormatter(_ pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = pattern
        return formatter
    }

    /// A cached formatter for `pattern`, building one on demand if it is not
    /// a known pattern.
    /// - Parameter pattern: A `DateFormatter` format string.
    /// - Returns: The formatter to parse with.
    static func formatter(for pattern: String) -> DateFormatter {
        formatterCache[pattern] ?? makeDateFormatter(pattern)
    }

    private static let dateFormatters: [DateFormatter] = datePatterns.map { formatter(for: $0) }

    // MARK: - RFC 4180 parsing / escaping

    /// Quotes a field for CSV output when it contains a comma, quote or
    /// newline, doubling any embedded quotes.
    /// - Parameter field: The raw value.
    /// - Returns: The value, quoted only if it needs to be.
    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Splits CSV text into rows of fields, honouring quoted fields that contain
    /// commas, escaped quotes and embedded newlines.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var insideQuotes = false
        var iterator = text.startIndex

        /// Closes the field being accumulated and starts the next one.
        func endField() {
            currentRow.append(currentField)
            currentField = ""
        }
        /// Closes the current field and the row it completes.
        func endRow() {
            endField()
            rows.append(currentRow)
            currentRow = []
        }

        while iterator < text.endIndex {
            let character = text[iterator]
            if insideQuotes {
                if character == "\"" {
                    let next = text.index(after: iterator)
                    if next < text.endIndex, text[next] == "\"" {
                        currentField.append("\"")
                        iterator = next
                    } else {
                        insideQuotes = false
                    }
                } else if character == "\r\n" || character == "\r" {
                    // Keep embedded line breaks, but normalise them.
                    currentField.append("\n")
                } else {
                    currentField.append(character)
                }
            } else {
                switch character {
                case "\"":
                    insideQuotes = true
                case ",":
                    endField()
                // Swift treats "\r\n" as ONE Character (a single grapheme cluster),
                // so it has to be matched explicitly — it is not a "\r" then a "\n".
                case "\r\n", "\n", "\r":
                    endRow()
                default:
                    currentField.append(character)
                }
            }
            iterator = text.index(after: iterator)
        }

        if !currentField.isEmpty || !currentRow.isEmpty {
            endRow()
        }
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }

    /// Reduces a header to letters and digits so "Account Type", "account_type"
    /// and "AccountType" all match the same alias.
    private static func normalizeKey(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
