import Foundation
import SwiftData

@Model
final class Transaction {

    var id: UUID = UUID()
    var title: String = ""
    /// Always stored as a positive magnitude; `type` decides the sign.
    var amount: Decimal = Decimal.zero
    var typeRaw: String = TransactionType.expense.rawValue
    var date: Date = Date()
    var note: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var account: Account?
    var category: Category?

    /// Set when this transaction was generated from a recurring rule.
    var recurringRule: RecurringRule?

    /// Creates a transaction. `amount` is stored as its magnitude — the sign
    /// comes from `type`.
    /// - Parameters:
    ///   - id: Stable identifier; a fresh UUID unless importing or restoring.
    ///   - title: Display title.
    ///   - amount: Magnitude; the absolute value is stored.
    ///   - type: Expense or income.
    ///   - date: When it happened; a future date makes it scheduled.
    ///   - note: Free-text note.
    ///   - account: Owning account, if any.
    ///   - category: Category, if any.
    ///   - recurringRule: Rule that generated this, when applicable.
    ///   - createdAt: Creation timestamp; also seeds `updatedAt`.
    init(
        id: UUID = UUID(),
        title: String,
        amount: Decimal,
        type: TransactionType,
        date: Date,
        note: String = "",
        account: Account? = nil,
        category: Category? = nil,
        recurringRule: RecurringRule? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.amount = abs(amount)
        self.typeRaw = type.rawValue
        self.date = date
        self.note = note
        self.account = account
        self.category = category
        self.recurringRule = recurringRule
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// Typed view of `typeRaw`; falls back to `.expense` on an unknown value.
    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    /// Amount with its sign applied — negative for expenses, positive for income.
    var signedAmount: Decimal { abs(amount) * type.sign }

    /// A transaction dated in the future — shown separately as "Upcoming".
    var isScheduled: Bool { date > Date.now.endOfDay }

    /// True when a recurring rule generated this transaction.
    var isRecurringInstance: Bool { recurringRule != nil }
}
