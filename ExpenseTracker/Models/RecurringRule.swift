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
    var category: Category?

    /// Generated transactions are kept if the rule is deleted, so history survives.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.recurringRule)
    var transactions: [Transaction]? = []

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
        self.category = category
        self.isActive = true
        self.lastPostedIndex = -1
        self.createdAt = createdAt
    }

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

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
            value: index * interval,
            to: startDate
        )
    }

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
