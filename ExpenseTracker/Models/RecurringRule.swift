import Foundation
import SwiftData

/// A repeating transaction template — subscriptions, rent, salary, EMIs.
@Model
final class RecurringRule {
    var id: UUID = UUID()
    var title: String = ""
    var amount: Decimal = Decimal.zero
    var typeRaw: String = TransactionType.expense.rawValue
    var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
    /// Repeat every `interval` units of `frequency` — e.g. 2 + .weekly is fortnightly.
    var interval: Int = 1
    var startDate: Date = Date()
    var endDate: Date?
    var note: String = ""
    var isActive: Bool = true
    /// Highest occurrence index already turned into a Transaction; -1 means none yet.
    var lastPostedIndex: Int = -1
    var createdAt: Date = Date()

    var account: Account?
    /// Set instead of `account` when the charge lands on a credit card.
    var creditCard: CreditCard?
    var category: Category?

    /// Generated transactions are kept if the rule is deleted, so history survives.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.recurringRule)
    var transactions: [Transaction]? = []

    /// Creates a recurring rule. Dates are normalised to day bounds so
    /// occurrence maths never drifts by hours.
    /// - Parameters:
    ///   - id: Stable identifier; a fresh UUID unless restoring from a backup.
    ///   - title: Title given to each generated transaction.
    ///   - amount: Magnitude; the absolute value is stored.
    ///   - type: Expense or income.
    ///   - frequency: Day, week, month or year.
    ///   - interval: Units per repeat; clamped to at least 1.
    ///   - startDate: First occurrence, snapped to the start of that day.
    ///   - endDate: Last day covered, snapped to the end of that day; nil runs forever.
    ///   - note: Free-text note copied onto generated transactions.
    ///   - account: Bank account to post into.
    ///   - creditCard: Credit card to charge instead of a bank account.
    ///   - category: Category to tag generated transactions with.
    ///   - createdAt: Creation timestamp.
    init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal,
        type: TransactionType,
        frequency: RecurrenceFrequency,
        interval: Int = 1,
        startDate: Date,
        endDate: Date? = nil,
        note: String = "",
        account: Account? = nil,
        creditCard: CreditCard? = nil,
        category: Category? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.amount = abs(amount)
        self.typeRaw = type.rawValue
        self.frequencyRaw = frequency.rawValue
        self.interval = max(1, interval)
        self.startDate = startDate.startOfDay
        self.endDate = endDate?.endOfDay
        self.note = note
        self.account = account
        self.creditCard = creditCard
        self.category = category
        self.isActive = true
        self.lastPostedIndex = -1
        self.createdAt = createdAt
    }

    /// Where the generated transactions are charged, for the pickers that offer
    /// accounts and cards in one list.
    var paymentSource: PaymentSource? {
        if let creditCard { return .creditCard(creditCard.id) }
        if let account { return .account(account.id) }
        return nil
    }

    /// Name of the account or card charged, for rows that show it.
    var sourceName: String? { creditCard?.name ?? account?.name }

    /// Typed view of `typeRaw`; falls back to `.expense` on an unknown value.
    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    /// Typed view of `frequencyRaw`; falls back to `.monthly` on an unknown value.
    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    /// Human-readable cadence, e.g. "Every month" or "Every 2 weeks".
    var summary: String {
        interval == 1
            ? "Every \(frequency.unitLabel(interval: 1))"
            : "Every \(interval) \(frequency.unitLabel(interval: interval))"
    }

    // MARK: - Occurrence maths

    /// Date of the nth occurrence, always measured from `startDate` so months never drift
    /// (a rule starting Jan 31 lands on Feb 28, then Mar 31 again — not Feb 28, Mar 28).
    func occurrenceDate(at index: Int) -> Date? {
        guard index >= 0 else { return nil }
        guard index > 0 else { return startDate }
        return Calendar.current.date(
            byAdding: frequency.calendarComponent,
            value: index * interval * frequency.stepsPerUnit,
            to: startDate
        )
    }

    /// Whether `date` falls inside the rule's start/end window.
    /// - Parameter date: The date to test.
    /// - Returns: True when the rule still covers that date.
    func isWithinRange(_ date: Date) -> Bool {
        guard date >= startDate.startOfDay else { return false }
        if let endDate { return date <= endDate }
        return true
    }

    /// The next occurrence strictly after `date` that the rule still covers.
    func nextOccurrence(after date: Date = .now) -> Date? {
        var index = max(0, lastPostedIndex)
        // Walk forward with a generous bound so a long-dormant rule still resolves.
        for _ in 0...5000 {
            guard let candidate = occurrenceDate(at: index) else { return nil }
            if let endDate, candidate > endDate { return nil }
            if candidate > date { return candidate }
            index += 1
        }
        return nil
    }

    /// Occurrence indexes that should exist as transactions on or before `date`
    /// but have not been posted yet.
    func pendingIndexes(upTo date: Date) -> [Int] {
        var result: [Int] = []
        var index = lastPostedIndex + 1
        let limit = date.endOfDay
        while let candidate = occurrenceDate(at: index) {
            if let endDate, candidate > endDate { break }
            if candidate > limit { break }
            result.append(index)
            index += 1
            // Safety valve against a runaway rule creating thousands of rows at once.
            if result.count >= 1000 { break }
        }
        return result
    }
}
