import Foundation
import SwiftData

/// A credit card. Unlike an `Account`, which holds money you have, a card holds
/// money you have borrowed: spending raises `outstanding` and lowers the credit
/// left to spend, and a bill payment from a bank account brings it back down.
@Model
final class CreditCard {

    var id: UUID = UUID()
    var name: String = ""
    /// The card's total credit limit. `availableCredit` counts down from here.
    var creditLimit: Decimal = Decimal.zero
    /// Day of the month the statement closes, 1–31, clamped to the month's length.
    var statementDay: Int = 1
    /// Day of the month the bill is due, 1–31, clamped the same way.
    var dueDay: Int = 20
    /// What was already owed on the card before any transaction in this app.
    /// Positive means money owed.
    var openingOutstanding: Decimal = Decimal.zero
    var colorHex: String = Theme.paletteHexes[0]
    var symbolName: String = "creditcard"
    var isArchived: Bool = false
    var sortIndex: Int = 0
    var note: String = ""
    var createdAt: Date = Date()

    /// Deleting a card removes its spending and its bill payments — the UI warns first.
    @Relationship(deleteRule: .cascade, inverse: \Transaction.creditCard)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringRule.creditCard)
    var recurringRules: [RecurringRule]? = []

    /// Creates a credit card.
    /// - Parameters:
    ///   - id: Stable identifier; a fresh UUID unless restoring from a backup.
    ///   - name: Display name.
    ///   - creditLimit: Total credit the issuer allows.
    ///   - statementDay: Day of month the statement closes; clamped to 1...31.
    ///   - dueDay: Day of month the bill is due; clamped to 1...31.
    ///   - openingOutstanding: Amount already owed before tracking started.
    ///   - colorHex: Accent colour; defaults to the first palette entry.
    ///   - symbolName: SF Symbol shown on the badge.
    ///   - sortIndex: Position in the cards list.
    ///   - note: Free-text note.
    ///   - createdAt: Creation timestamp.
    init(
        id: UUID = UUID(),
        name: String,
        creditLimit: Decimal = .zero,
        statementDay: Int = 1,
        dueDay: Int = 20,
        openingOutstanding: Decimal = .zero,
        colorHex: String = Theme.paletteHexes[0],
        symbolName: String = "creditcard",
        sortIndex: Int = 0,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.creditLimit = max(.zero, creditLimit)
        self.statementDay = BillingCycle.clampDayOfMonth(statementDay)
        self.dueDay = BillingCycle.clampDayOfMonth(dueDay)
        self.openingOutstanding = openingOutstanding
        self.colorHex = colorHex
        self.symbolName = symbolName
        self.isArchived = false
        self.sortIndex = sortIndex
        self.note = note
        self.createdAt = createdAt
    }

    // MARK: - Balances

    /// Everything owed on the card right now: what was owed before tracking
    /// started, plus every purchase, less every refund and bill payment.
    var outstanding: Decimal {
        (transactions ?? []).reduce(openingOutstanding) { $0 + $1.creditCardImpact }
    }

    /// `outstanding` counting only transactions dated on or before `date`, so a
    /// future-dated charge doesn't eat into the credit you can spend today.
    /// - Parameter date: The day to settle the balance at; defaults to today.
    /// - Returns: What is owed as of that day.
    func outstanding(asOf date: Date) -> Decimal {
        let cutoff = date.endOfDay
        return (transactions ?? [])
            .filter { $0.date <= cutoff }
            .reduce(openingOutstanding) { $0 + $1.creditCardImpact }
    }

    /// `outstanding` as of today.
    var clearedOutstanding: Decimal { outstanding(asOf: .now) }

    /// Credit still available to spend. Never reported below zero, and only
    /// meaningful once a limit has been set.
    var availableCredit: Decimal {
        max(.zero, creditLimit - clearedOutstanding)
    }

    /// How much of the limit is used, 0...1. Zero when no limit is set yet.
    var utilisation: Double {
        guard creditLimit > 0 else { return 0 }
        let ratio = (clearedOutstanding / creditLimit).doubleValue
        return min(1, max(0, ratio))
    }

    /// A card with no limit entered can't report available credit or utilisation,
    /// so the UI nudges the user to fill it in.
    var hasCreditLimit: Bool { creditLimit > 0 }

    // MARK: - Billing

    /// The statement period that has most recently closed, whose balance is
    /// what the next payment covers.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: The closed cycle's window and due date.
    func lastClosedCycle(asOf date: Date = .now) -> BillingCycle {
        BillingCycle.lastClosed(statementDay: statementDay, dueDay: dueDay, asOf: date)
    }

    /// The period charges are landing in now — it hasn't been billed yet.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: The open cycle's window and the due date it will carry.
    func currentCycle(asOf date: Date = .now) -> BillingCycle {
        BillingCycle.current(statementDay: statementDay, dueDay: dueDay, asOf: date)
    }

    /// What the last statement closed at: everything owed on the card as of the
    /// statement date, carried-over balance included.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: The balance on the statement.
    func statementBalance(asOf date: Date = .now) -> Decimal {
        let close = lastClosedCycle(asOf: date).end
        return (transactions ?? [])
            .filter { $0.date <= close }
            .reduce(openingOutstanding) { $0 + $1.creditCardImpact }
    }

    /// The bill still to pay: the last statement's balance less anything already
    /// paid towards it since the statement closed. Never negative — overpaying
    /// leaves a credit on `outstanding` rather than a negative amount due.
    ///
    /// A refund landing after the statement closed pays part of that statement
    /// down without being a payment, so it counts too — otherwise the card would
    /// be billed for money it no longer owes, and paying would push it into
    /// credit. This holds however much has been spent in the new cycle since.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: What is left to pay.
    func amountDue(asOf date: Date = .now) -> Decimal {
        let close = lastClosedCycle(asOf: date).end
        // Anything landing after the statement that brings the balance down
        // settles part of it — a bill payment, and equally a refund the merchant
        // put through. New charges after the close belong to the next statement,
        // so they are ignored rather than added to what is owed now. Both are
        // capped at the reference date, so a payment scheduled for next week
        // doesn't settle this week's bill before it is made.
        let settledSinceClose = (transactions ?? [])
            .filter { $0.date > close && $0.date <= date.endOfDay }
            .reduce(Decimal.zero) { $0 + max(.zero, -$1.creditCardImpact) }
        return max(.zero, (statementBalance(asOf: date) - settledSinceClose).roundedToCurrency)
    }

    /// Charges made since the last statement closed — what the *next* bill will
    /// be built from. Payments are left out; they settle the previous bill.
    ///
    /// Stops at `date` rather than running to the end of the cycle, matching
    /// `outstanding(asOf:)`: a charge scheduled for later this cycle will be on
    /// that bill, but it has not been spent yet, and the overview already lists
    /// it under Upcoming.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: The unbilled spend on the card so far.
    func currentCycleSpend(asOf date: Date = .now) -> Decimal {
        let cycle = currentCycle(asOf: date)
        let cutoff = date.endOfDay
        return (transactions ?? [])
            .filter { $0.kind != .cardPayment && cycle.contains($0.date) && $0.date <= cutoff }
            .reduce(Decimal.zero) { $0 + $1.creditCardImpact }
    }

    /// True once the last statement's bill is settled, so the dashboard can
    /// show the card as clear instead of offering a zero payment.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: Whether nothing is owed on the last statement.
    func isSettled(asOf date: Date = .now) -> Bool {
        amountDue(asOf: date) <= 0
    }
}
