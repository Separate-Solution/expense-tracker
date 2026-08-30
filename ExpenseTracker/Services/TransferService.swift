import Foundation
import SwiftData

/// Moving money between two of your own accounts. Like a card bill payment this
/// is one transaction touching both ends, marked `.transfer` so it stays out of
/// income and spending totals — nothing was earned or spent, the money is just
/// sitting somewhere else.
enum TransferService {

    /// Why a transfer can't be made, for the sheet to explain rather than just
    /// disabling its button.
    enum Failure: LocalizedError, Equatable {
        case sameAccount
        case nonPositiveAmount

        var errorDescription: String? {
            switch self {
            case .sameAccount:
                return "Pick two different accounts — money can't move to where it already is."
            case .nonPositiveAmount:
                return "Enter an amount greater than zero."
            }
        }
    }

    /// Records a transfer between two accounts.
    /// - Parameters:
    ///   - source: The account the money leaves.
    ///   - destination: The account it lands in.
    ///   - amount: How much to move; the magnitude is used.
    ///   - date: When it happened; defaults to now.
    ///   - note: Free-text note.
    ///   - context: Context to insert into. The caller does not need to save.
    /// - Returns: The inserted transaction.
    /// - Throws: `Failure` when the two sides match or the amount isn't positive.
    @discardableResult
    static func transfer(
        from source: Account,
        to destination: Account,
        amount: Decimal,
        date: Date = .now,
        note: String = "",
        in context: ModelContext
    ) throws -> Transaction {
        guard source.id != destination.id else { throw Failure.sameAccount }
        let value = abs(amount).roundedToCurrency
        guard value > 0 else { throw Failure.nonPositiveAmount }

        let movement = Transaction(
            title: "Transfer · \(destination.name)",
            amount: value,
            // An expense on the source's side, so the balance maths that already
            // exists takes the money out; the destination picks it up through
            // `incomingTransfers`.
            type: .expense,
            date: date,
            note: note,
            kind: .transfer,
            account: source,
            toAccount: destination,
            category: nil
        )
        context.insert(movement)
        do {
            try context.save()
        } catch {
            // The sheet reports what it is told, so a swallowed failure would
            // dismiss on a success it never had. Take the half-made row back
            // out too, or the next successful save anywhere would commit it.
            context.delete(movement)
            throw error
        }
        return movement
    }
}
