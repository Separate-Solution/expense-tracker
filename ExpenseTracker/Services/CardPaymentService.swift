import Foundation
import SwiftData

/// Settling a credit card bill. The payment is one transaction that both
/// reduces the bank account's balance and clears the card's outstanding, and it
/// is marked `.cardPayment` so it stays out of income and spending totals — the
/// purchases it settles were already counted when they were made.
enum CardPaymentService {

    /// Records a bill payment from a bank account to a credit card.
    /// - Parameters:
    ///   - card: The card being paid off.
    ///   - account: The bank account the money leaves.
    ///   - amount: How much to pay; the magnitude is used.
    ///   - date: When the payment happened; defaults to now.
    ///   - context: Context to insert into. The caller does not need to save.
    /// - Returns: The inserted transaction, or nil for a non-positive amount.
    /// - Throws: Any error from saving, so a failed payment isn't reported as
    ///   a success by the sheet that asked for it.
    @discardableResult
    static func pay(
        card: CreditCard,
        from account: Account,
        amount: Decimal,
        date: Date = .now,
        in context: ModelContext
    ) throws -> Transaction? {
        let value = abs(amount).roundedToCurrency
        guard value > 0 else { return nil }

        let payment = Transaction(
            title: "Payment · \(card.name)",
            amount: value,
            // An expense on the bank account's side, so the balance maths that
            // already exists takes the money out without a special case.
            type: .expense,
            date: date,
            kind: .cardPayment,
            account: account,
            creditCard: card,
            category: nil
        )
        context.insert(payment)
        do {
            try context.save()
        } catch {
            // Take the half-made payment back out, or the next successful save
            // anywhere in the app would commit one the user was told had failed.
            context.delete(payment)
            throw error
        }
        return payment
    }

    /// Clears the whole of a card's outstanding bill in one go — what the
    /// dashboard's one-tap button does.
    /// - Parameters:
    ///   - card: The card being paid off.
    ///   - account: The bank account the money leaves.
    ///   - date: When the payment happened; defaults to now.
    ///   - context: Context to insert into.
    /// - Returns: The inserted transaction, or nil when nothing is due.
    /// - Throws: Any error from saving.
    @discardableResult
    static func payFullBill(
        card: CreditCard,
        from account: Account,
        date: Date = .now,
        in context: ModelContext
    ) throws -> Transaction? {
        try pay(card: card, from: account, amount: card.amountDue(asOf: date), date: date, in: context)
    }
}
