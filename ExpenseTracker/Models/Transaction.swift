import Foundation
import SwiftData

@Model
final class Transaction {

    var id: UUID = UUID()
    var title: String = ""
    /// Always stored as a positive magnitude; `type` decides the sign.
    var amount: Decimal = Decimal.zero
    var typeRaw: String = TransactionType.expense.rawValue
    /// Standard spending/income, or a credit card bill payment.
    var kindRaw: String = TransactionKind.standard.rawValue
    var date: Date = Date()
    var note: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Bank account the money moved through. On a card payment this is the
    /// account the bill was paid *from*.
    var account: Account?
    /// Credit card the money moved through. On a card payment this is the card
    /// being paid *off*; on a purchase it is the card that was swiped.
    var creditCard: CreditCard?
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
    ///   - kind: Standard transaction or a credit card bill payment.
    ///   - account: Owning bank account, if any.
    ///   - creditCard: Owning credit card, if any.
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
        kind: TransactionKind = .standard,
        account: Account? = nil,
        creditCard: CreditCard? = nil,
        category: Category? = nil,
        recurringRule: RecurringRule? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.amount = abs(amount)
        self.typeRaw = type.rawValue
        self.kindRaw = kind.rawValue
        self.date = date
        self.note = note
        self.account = account
        self.creditCard = creditCard
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

    /// Typed view of `kindRaw`; falls back to `.standard` on an unknown value.
    var kind: TransactionKind {
        get { TransactionKind(rawValue: kindRaw) ?? .standard }
        set { kindRaw = newValue.rawValue }
    }

    /// Amount with its sign applied — negative for expenses, positive for income.
    var signedAmount: Decimal { abs(amount) * type.sign }

    /// True when this row settles a credit card bill rather than recording
    /// spending. Such rows are kept out of income and expense totals.
    var isCardPayment: Bool { kind == .cardPayment }

    /// Whether this belongs in the month's income and spending figures.
    var countsTowardsTotals: Bool { kind.countsTowardsTotals }

    /// Effect on the linked card's outstanding balance. A purchase adds to what
    /// is owed; a refund and a bill payment both bring it down. Zero when no
    /// card is involved.
    var creditCardImpact: Decimal {
        guard creditCard != nil else { return .zero }
        if isCardPayment { return -abs(amount) }
        return abs(amount) * (type == .expense ? 1 : -1)
    }

    /// Where the money moved, for the pickers that offer accounts and cards
    /// in one list. A card payment reports the bank account it was paid from.
    var paymentSource: PaymentSource? {
        if isCardPayment { return account.map { .account($0.id) } }
        if let creditCard { return .creditCard(creditCard.id) }
        if let account { return .account(account.id) }
        return nil
    }

    /// Name of the account or card the money moved through, for rows and search.
    var sourceName: String? {
        if isCardPayment { return account?.name }
        return creditCard?.name ?? account?.name
    }

    /// A transaction dated in the future — shown separately as "Upcoming".
    var isScheduled: Bool { date > Date.now.endOfDay }

    /// True when a recurring rule generated this transaction.
    var isRecurringInstance: Bool { recurringRule != nil }

    /// An unsaved copy of this transaction, ready to insert into a context.
    ///
    /// The copy gets a fresh id and creation stamp but keeps the original's
    /// date and time. It is deliberately *not* tied to the recurring rule —
    /// only the recurrence engine posts occurrences of a rule, so a hand-made
    /// duplicate stands on its own.
    /// - Parameter createdAt: Creation stamp for the copy; defaults to now.
    /// - Returns: The new, uninserted transaction.
    func duplicated(createdAt: Date = Date()) -> Transaction {
        Transaction(
            title: title,
            amount: amount,
            type: type,
            date: date,
            note: note,
            kind: kind,
            account: account,
            creditCard: creditCard,
            category: category,
            createdAt: createdAt
        )
    }
}
