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

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var signedAmount: Decimal { abs(amount) * type.sign }

    /// A transaction dated in the future — shown separately as "Upcoming".
    var isScheduled: Bool { date > Date.now.endOfDay }

    var isRecurringInstance: Bool { recurringRule != nil }
}
