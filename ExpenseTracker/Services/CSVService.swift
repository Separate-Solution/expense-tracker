import Foundation
import SwiftData

struct CSVImportSummary {
    var imported: Int = 0
    var skippedDuplicates: Int = 0
    var createdAccounts: [String] = []
    var createdCategories: [String] = []
    var failures: [String] = []

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

enum CSVService {

    static let exportHeader = [
        "Date", "Title", "Type", "Amount", "Currency",
        "Account", "Account Type", "Category", "Note", "ID"
    ]

    // MARK: - Export

    static func exportString(transactions: [Transaction]) -> String {
        var rows = [exportHeader.map(escape).joined(separator: ",")]
        let sorted = transactions.sorted { $0.date < $1.date }
        for transaction in sorted {
            let fields = [
                isoDateFormatter.string(from: transaction.date),
                transaction.title,
                transaction.type.title,
                NSDecimalNumber(decimal: transaction.amount.roundedToCurrency)
                    .description(withLocale: Locale(identifier: "en_US_POSIX")),
                Formatters.currencyCode,
                transaction.account?.name ?? "",
                transaction.account?.kind.rawValue ?? "",
                transaction.category?.name ?? "",
                transaction.note,
                transaction.id.uuidString
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    // MARK: - Import

    /// Parses `text` and inserts transactions, creating any account or category
    /// named in the file that does not exist yet. Rows whose ID already exists
    /// are skipped so re-importing the same export is safe.
    static func importTransactions(
        from text: String,
        into context: ModelContext,
        defaultAccount: Account?
    ) throws -> CSVImportSummary {
        let rows = parse(text)
        guard let headerRow = rows.first, rows.count > 1 else { throw CSVError.emptyFile }

        let header = headerRow.map(normalizeKey)
        func column(_ candidates: [String]) -> Int? {
            for candidate in candidates {
                if let index = header.firstIndex(of: candidate) { return index }
            }
            return nil
        }

        let dateIndex = column(["date", "transactiondate", "day"])
        let amountIndex = column(["amount", "value", "sum"])
        var missing: [String] = []
        if dateIndex == nil { missing.append("Date") }
        if amountIndex == nil { missing.append("Amount") }
        guard missing.isEmpty, let dateIndex, let amountIndex else {
            throw CSVError.missingRequiredColumns(missing)
        }

        let titleIndex = column(["title", "name", "description", "note title", "payee", "merchant"])
        let typeIndex = column(["type", "transactiontype", "kind", "direction"])
        let accountIndex = column(["account", "accountname"])
        let accountTypeIndex = column(["accounttype", "accountkind"])
        let categoryIndex = column(["category", "categoryname"])
        let noteIndex = column(["note", "notes", "memo", "comment"])
        let idIndex = column(["id", "uuid", "transactionid"])
        // Cashew-specific extras, used when present to preserve more of the export.
        let incomeIndex = column(["income", "isincome"])
        let colorIndex = column(["color", "categorycolor"])
        let iconIndex = column(["icon", "categoryicon"])
        let emojiIndex = column(["emoji", "categoryemoji"])

        var summary = CSVImportSummary()
        var accountCache = try existingAccountsByName(in: context)
        var categoryCache = try existingCategoriesByKey(in: context)
        let existingIDs = try existingTransactionIDs(in: context)
        var seenIDs = existingIDs

        for (offset, row) in rows.dropFirst().enumerated() {
            let lineNumber = offset + 2
            func field(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let rawRow = row.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if rawRow.isEmpty { continue }

            guard let date = parseDate(field(dateIndex)) else {
                summary.failures.append("Line \(lineNumber): couldn't read the date “\(field(dateIndex))”.")
                continue
            }
            guard let signedAmount = parseAmount(field(amountIndex)) else {
                summary.failures.append("Line \(lineNumber): couldn't read the amount “\(field(amountIndex))”.")
                continue
            }

            // A boolean "income" column is the most reliable signal (Cashew writes one),
            // then an explicit type word, then finally the sign of the amount.
            let type: TransactionType
            if let isIncome = parseBool(field(incomeIndex)) {
                type = isIncome ? .income : .expense
            } else if let explicit = parseType(field(typeIndex)) {
                type = explicit
            } else {
                type = signedAmount < 0 ? .expense : .income
            }

            if let idText = idIndex.map({ _ in field(idIndex) }),
               let uuid = UUID(uuidString: idText) {
                if seenIDs.contains(uuid) {
                    summary.skippedDuplicates += 1
                    continue
                }
                seenIDs.insert(uuid)
            }

            let accountName = field(accountIndex)
            var account = defaultAccount
            if !accountName.isEmpty {
                let key = accountName.lowercased()
                if let existing = accountCache[key] {
                    account = existing
                } else {
                    let kind = AccountKind(rawValue: field(accountTypeIndex).lowercased())
                        ?? inferAccountKind(from: accountName)
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

            let categoryName = field(categoryIndex)
            var category: Category?
            if !categoryName.isEmpty {
                let key = "\(type.rawValue)|\(categoryName.lowercased())"
                if let existing = categoryCache[key] {
                    category = existing
                } else {
                    let created = Category(
                        name: categoryName,
                        emoji: categoryEmoji(
                            explicit: field(emojiIndex),
                            iconName: field(iconIndex),
                            type: type
                        ),
                        colorHex: parseColorHex(field(colorIndex))
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

            let title = field(titleIndex).isEmpty
                ? (category?.name ?? "Imported transaction")
                : field(titleIndex)

            let transaction = Transaction(
                id: idIndex.flatMap { _ in UUID(uuidString: field(idIndex)) } ?? UUID(),
                title: title,
                amount: abs(signedAmount).roundedToCurrency,
                type: type,
                date: date,
                note: field(noteIndex),
                account: account,
                category: category
            )
            context.insert(transaction)
            summary.imported += 1
        }

        try context.save()
        return summary
    }

    // MARK: - Lookups

    private static func existingAccountsByName(in context: ModelContext) throws -> [String: Account] {
        let accounts = try context.fetch(FetchDescriptor<Account>())
        return Dictionary(accounts.map { ($0.name.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func existingCategoriesByKey(in context: ModelContext) throws -> [String: Category] {
        let categories = try context.fetch(FetchDescriptor<Category>())
        return Dictionary(
            categories.map { ("\($0.type.rawValue)|\($0.name.lowercased())", $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func existingTransactionIDs(in context: ModelContext) throws -> Set<UUID> {
        Set(try context.fetch(FetchDescriptor<Transaction>()).map(\.id))
    }

    // MARK: - Field parsing

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

    /// Cashew stores an icon name rather than an emoji; map the common ones so
    /// imported categories don't all come in as a generic tag.
    private static let iconEmoji: [String: String] = [
        "groceries": "🛒", "cutlery": "🍔", "food": "🍔", "restaurant": "🍽️",
        "coffee": "☕️", "tram": "🚕", "car": "🚗", "fuel": "⛽️", "bus": "🚌",
        "bills": "💡", "home": "🏠", "rent": "🏠", "subscription": "🔁",
        "coin": "💰", "money": "💰", "salary": "💼", "work": "💼",
        "loan": "🤝", "charts": "📊", "popcorn": "🎬", "movie": "🎬",
        "shopping": "🛍️", "gift": "🎁", "health": "💊", "medical": "💊",
        "travel": "✈️", "flight": "✈️", "education": "📚", "book": "📚",
        "phone": "📱", "internet": "🌐", "pet": "🐶", "baby": "👶",
        "fitness": "🏋️", "beauty": "🧴", "investment": "📈", "bank": "🏦"
    ]

    static func categoryEmoji(explicit: String, iconName: String, type: TransactionType) -> String {
        let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, first.isEmoji { return String(first) }
        let key = iconName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let mapped = iconEmoji[key] { return mapped }
        return type == .expense ? "🏷️" : "💰"
    }

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

    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for formatter in dateFormatters {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return ISO8601DateFormatter().date(from: trimmed)
    }

    private static func inferAccountKind(from name: String) -> AccountKind {
        let lowered = name.lowercased()
        if lowered.contains("cash") || lowered.contains("wallet") { return .cash }
        if lowered.contains("card") || lowered.contains("credit") || lowered.contains("visa")
            || lowered.contains("amex") || lowered.contains("mastercard") { return .credit }
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

    private static let dateFormatters: [DateFormatter] = {
        let patterns = [
            // Most specific first — Cashew exports "2026-08-12 18:04:13.000".
            "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd", "yyyy/MM/dd HH:mm:ss", "yyyy/MM/dd",
            "dd-MM-yyyy HH:mm:ss", "dd/MM/yyyy HH:mm:ss",
            "dd-MM-yyyy", "dd/MM/yyyy", "MM/dd/yyyy",
            "dd MMM yyyy", "MMM dd, yyyy", "dd-MMM-yyyy"
        ]
        return patterns.map { pattern in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = pattern
            return formatter
        }
    }()

    // MARK: - RFC 4180 parsing / escaping

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

        func endField() {
            currentRow.append(currentField)
            currentField = ""
        }
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

    private static func normalizeKey(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
