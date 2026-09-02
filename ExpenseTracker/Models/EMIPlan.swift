import Foundation
import SwiftData

/// A loan repaid in equal installments over a fixed number of periods — a phone
/// bought on EMI, a personal loan, a card purchase converted to installments.
///
/// Unlike a `RecurringRule`, which repeats until it is stopped, an EMI plan runs
/// for a known number of installments and then finishes. It also knows what the
/// money costs — the rate it carries and what closing it early would cost — so
/// the plan can say what is still owed rather than only what is still to post.
@Model
final class EMIPlan {

    var id: UUID = UUID()
    var title: String = ""
    /// The financed amount the installments pay off, before interest.
    var principal: Decimal = Decimal.zero
    /// Annual rate as a percentage — 13.5 means 13.5% a year. Zero is a
    /// no-cost EMI, where the installments just divide the principal up.
    var annualInterestRate: Decimal = Decimal.zero
    /// What the lender charges to close the plan early, as a percentage of the
    /// principal still outstanding at that point.
    var foreclosureChargePercent: Decimal = Decimal.zero
    var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
    /// One installment every `interval` units of `frequency` — 2 + .monthly is
    /// every second month.
    var interval: Int = 1
    /// How many installments the plan runs for.
    var installmentCount: Int = 12
    /// What one installment costs. Suggested from the loan terms, but stored
    /// separately because the lender's figure is the one that matters and the
    /// user can type it in.
    var installmentAmount: Decimal = Decimal.zero
    var startDate: Date = Date()
    var statusRaw: String = EMIStatus.active.rawValue
    /// Highest installment index already turned into a Transaction; -1 means none yet.
    var lastPostedIndex: Int = -1
    /// When the plan stopped running — the day it completed or was foreclosed.
    var closedDate: Date?
    /// The settlement transaction that foreclosed the plan, so it can be told
    /// apart from the installments it closed.
    var closingPaymentID: UUID?
    var note: String = ""
    var createdAt: Date = Date()

    var account: Account?
    /// Set instead of `account` when the installments are charged to a card.
    var creditCard: CreditCard?
    var category: Category?

    /// Posted installments, plus the settlement payment on a foreclosed plan.
    /// Deleting the plan keeps them, so the history of what was paid survives.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.emiPlan)
    var transactions: [Transaction]? = []

    /// Creates an EMI plan.
    /// - Parameters:
    ///   - id: Stable identifier; a fresh UUID unless restoring from a backup.
    ///   - title: Name given to the plan and to each installment it posts.
    ///   - principal: The financed amount; the absolute value is stored.
    ///   - annualInterestRate: Annual rate as a percentage; negatives are clamped to zero.
    ///   - foreclosureChargePercent: Early-closure fee, as a percentage of the outstanding principal.
    ///   - frequency: How often an installment falls due.
    ///   - interval: Units per installment; clamped to at least 1.
    ///   - installmentCount: How many installments; clamped to at least 1.
    ///   - installmentAmount: What one installment costs; the suggestion when left at zero.
    ///   - startDate: First installment, snapped to the start of that day.
    ///   - note: Free-text note copied onto each installment.
    ///   - account: Bank account the installments come out of.
    ///   - creditCard: Credit card charged instead of a bank account.
    ///   - category: Category to tag the installments with.
    ///   - createdAt: Creation timestamp.
    init(
        id: UUID = UUID(),
        title: String,
        principal: Decimal,
        annualInterestRate: Decimal = .zero,
        foreclosureChargePercent: Decimal = .zero,
        frequency: RecurrenceFrequency = .monthly,
        interval: Int = 1,
        installmentCount: Int,
        installmentAmount: Decimal,
        startDate: Date,
        note: String = "",
        account: Account? = nil,
        creditCard: CreditCard? = nil,
        category: Category? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.principal = abs(principal)
        self.annualInterestRate = max(.zero, annualInterestRate)
        self.foreclosureChargePercent = max(.zero, foreclosureChargePercent)
        self.frequencyRaw = frequency.rawValue
        self.interval = max(1, interval)
        self.installmentCount = max(1, installmentCount)
        self.installmentAmount = abs(installmentAmount)
        self.startDate = startDate.startOfDay
        self.note = note
        self.account = account
        self.creditCard = creditCard
        self.category = category
        self.statusRaw = EMIStatus.active.rawValue
        self.lastPostedIndex = -1
        self.createdAt = createdAt
    }

    /// Typed view of `frequencyRaw`; falls back to `.monthly` on an unknown value.
    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    /// Typed view of `statusRaw`; falls back to `.active` on an unknown value.
    var status: EMIStatus {
        get { EMIStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    /// Where the installments are charged, for the pickers that offer accounts
    /// and cards in one list.
    var paymentSource: PaymentSource? {
        if let creditCard { return .creditCard(creditCard.id) }
        if let account { return .account(account.id) }
        return nil
    }

    /// Name of the account or card charged, for rows that show it.
    var sourceName: String? { creditCard?.name ?? account?.name }

    /// Human-readable cadence, e.g. "Every month" or "Every 2 weeks".
    var cadenceSummary: String {
        interval == 1
            ? "Every \(frequency.unitLabel(interval: 1))"
            : "Every \(interval) \(frequency.unitLabel(interval: interval))"
    }

    // MARK: - Schedule

    /// Date of the nth installment, always measured from `startDate` so months
    /// never drift (a plan starting Jan 31 lands on Feb 28, then Mar 31 again).
    /// - Parameter index: Zero-based installment index.
    /// - Returns: The due date, or nil when the index is outside the plan.
    func installmentDate(at index: Int) -> Date? {
        guard index >= 0, index < installmentCount else { return nil }
        guard index > 0 else { return startDate }
        return Calendar.current.date(
            byAdding: frequency.calendarComponent,
            value: index * interval * frequency.stepsPerUnit,
            to: startDate
        )
    }

    /// The day the last installment falls due, for "runs until" lines.
    var finalInstallmentDate: Date? { installmentDate(at: installmentCount - 1) }

    /// Installment indexes that should exist as transactions by `date` but have
    /// not been posted yet.
    /// - Parameter date: The day to catch up to.
    /// - Returns: The indexes still to post, in order.
    func pendingIndexes(upTo date: Date) -> [Int] {
        guard status.isRunning else { return [] }
        var result: [Int] = []
        let limit = date.endOfDay
        var index = lastPostedIndex + 1
        while index < installmentCount, let due = installmentDate(at: index), due <= limit {
            result.append(index)
            index += 1
        }
        return result
    }

    /// The next installment still to fall due after `date`.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: The due date, or nil once the plan has posted them all.
    func nextInstallmentDate(after date: Date = .now) -> Date? {
        guard status.isRunning else { return nil }
        for index in max(0, lastPostedIndex + 1)..<installmentCount {
            if let due = installmentDate(at: index), due > date { return due }
        }
        return nil
    }

    // MARK: - Installments

    /// The posted installments, in schedule order. The settlement payment that
    /// foreclosed the plan is left out — it closed the plan rather than being
    /// one of its installments, and carries no installment index.
    var installments: [Transaction] {
        (transactions ?? [])
            .filter { $0.emiInstallmentIndex != nil }
            .sorted { ($0.emiInstallmentIndex ?? 0) < ($1.emiInstallmentIndex ?? 0) }
    }

    /// The posted installment at one position in the schedule.
    ///
    /// Found by the index the installment carries rather than by its position in
    /// the list: a plan created after some installments were already due can
    /// skip those, so the first row posted is not necessarily the first
    /// installment.
    /// - Parameter index: Zero-based installment index.
    /// - Returns: The posted installment, or nil when it hasn't posted.
    func installment(at index: Int) -> Transaction? {
        (transactions ?? []).first { $0.emiInstallmentIndex == index }
    }

    /// How many installments the lender has charged so far. This is what the
    /// principal is amortised against — the loan moves on when the installment
    /// is charged, whether or not the card bill carrying it has been paid yet.
    var chargedCount: Int {
        min(installmentCount, max(0, lastPostedIndex + 1))
    }

    /// The payment that foreclosed the plan, if it was closed early.
    var closingPayment: Transaction? {
        guard let closingPaymentID else { return nil }
        return (transactions ?? []).first { $0.id == closingPaymentID }
    }

    /// Whether one posted installment has actually been paid.
    ///
    /// Out of a bank account it is paid the moment it posts — the money left the
    /// account. On a credit card it has only been charged: the money leaves when
    /// the statement carrying it is settled, so the installment waits for that
    /// bill to be cleared, exactly like every other purchase on the card.
    /// - Parameters:
    ///   - installment: The posted installment to judge.
    ///   - date: Reference point; defaults to now.
    /// - Returns: True once the money has actually gone.
    func isSettled(_ installment: Transaction, asOf date: Date = .now) -> Bool {
        guard let card = creditCard else { return installment.date <= date.endOfDay }
        let close = card.currentCycle(asOf: installment.date).end
        return card.isStatementSettled(closingAt: close, asOf: date)
    }

    /// How many installments have been paid.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: The count of settled installments.
    func paidCount(asOf date: Date = .now) -> Int {
        installments.filter { isSettled($0, asOf: date) }.count
    }

    /// How many installments are still to be paid — both those yet to post and
    /// those posted to a card whose bill has not been settled.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: The count still outstanding.
    func pendingCount(asOf date: Date = .now) -> Int {
        max(0, installmentCount - paidCount(asOf: date))
    }

    /// What has actually been paid towards the plan, the settlement payment on a
    /// foreclosed plan included.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: The amount paid so far.
    func amountPaid(asOf date: Date = .now) -> Decimal {
        let installmentTotal = installments
            .filter { isSettled($0, asOf: date) }
            .reduce(Decimal.zero) { $0 + abs($1.amount) }
        let closing = closingPayment.map { abs($0.amount) } ?? .zero
        return (installmentTotal + closing).roundedToCurrency
    }

    /// What is left to pay on the schedule as it stands. A closed plan owes
    /// nothing, whether it ran its course or was settled early.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: The amount still to pay.
    func amountRemaining(asOf date: Date = .now) -> Decimal {
        guard status.isRunning else { return .zero }
        return (installmentAmount * Decimal(pendingCount(asOf: date))).roundedToCurrency
    }

    /// Everything the plan costs if it runs to the end — every installment,
    /// interest included.
    var totalPayable: Decimal {
        (installmentAmount * Decimal(installmentCount)).roundedToCurrency
    }

    /// What the borrowing costs on top of the principal. Never reported below
    /// zero: an installment typed in under the no-interest figure would
    /// otherwise show as negative interest rather than as the rounding it is.
    var totalInterest: Decimal {
        max(.zero, (totalPayable - principal).roundedToCurrency)
    }

    /// How far through the plan the payments are, 0...1, for the progress bar.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: The fraction paid.
    func progress(asOf date: Date = .now) -> Double {
        guard installmentCount > 0 else { return 0 }
        if status == .completed { return 1 }
        return min(1, max(0, Double(paidCount(asOf: date)) / Double(installmentCount)))
    }

    // MARK: - Interest maths

    /// The interest rate for one installment period, as a fraction.
    ///
    /// A `Double` because the amortisation formula needs powers, which `Decimal`
    /// cannot do. Everything it feeds is a suggestion the user can overwrite,
    /// and the result is rounded back to currency before it is stored — no
    /// balance is ever carried in floating point.
    var periodRate: Double {
        let periods = frequency.periodsPerYear / Double(max(1, interval))
        guard periods > 0 else { return 0 }
        return (annualInterestRate.doubleValue / 100) / periods
    }

    /// The installment a lender would quote for these terms, on a reducing
    /// balance: `P·r·(1+r)^n / ((1+r)^n − 1)`. With no interest it is simply the
    /// principal split evenly.
    /// - Parameters:
    ///   - principal: The financed amount.
    ///   - periodRate: Interest per installment period, as a fraction.
    ///   - count: How many installments.
    /// - Returns: The suggested installment, rounded to currency.
    static func suggestedInstallment(
        principal: Decimal,
        periodRate: Double,
        count: Int
    ) -> Decimal {
        let periods = max(1, count)
        guard principal > 0 else { return .zero }
        guard periodRate > 0 else {
            return (principal / Decimal(periods)).roundedToCurrency
        }
        let growth = pow(1 + periodRate, Double(periods))
        let factor = periodRate * growth / (growth - 1)
        // An unusable rate falls back to splitting the principal evenly rather
        // than suggesting a figure built out of NaN.
        guard factor.isFinite, factor < 1e30 else {
            return (principal / Decimal(periods)).roundedToCurrency
        }
        return (principal * Decimal(factor)).roundedToCurrency
    }

    /// The installment suggested for this plan's own terms.
    var suggestedInstallment: Decimal {
        Self.suggestedInstallment(
            principal: principal,
            periodRate: periodRate,
            count: installmentCount
        )
    }

    /// The principal still owed after `charged` installments, on a reducing
    /// balance: `P(1+r)^k − E((1+r)^k − 1)/r`. This is what foreclosing has to
    /// clear — the remaining installments include interest that is never charged
    /// once the loan is closed, so paying them all off would overpay.
    ///
    /// Built from the stored installment rather than the suggested one, so a
    /// plan carrying the lender's own figure stays consistent with it.
    /// - Parameter charged: How many installments the lender has charged.
    /// - Returns: The outstanding principal, never below zero or above the original.
    func outstandingPrincipal(afterCharged charged: Int) -> Decimal {
        let periods = max(0, min(charged, installmentCount))
        guard principal > 0 else { return .zero }
        let rate = periodRate
        let balance: Decimal
        if rate > 0 {
            let growth = pow(1 + rate, Double(periods))
            let repaidFactor = (growth - 1) / rate
            // A rate and term extreme enough to take these past what `Decimal`
            // can hold turn every figure built on them into NaN, which would
            // reach the screen as a quote of "NaN". The balance in that case is
            // far beyond the principal anyway, so the cap this is already held
            // to is the honest answer.
            guard growth.isFinite, repaidFactor.isFinite,
                  growth < 1e30, repaidFactor < 1e30 else { return principal }
            let paidOff = installmentAmount * Decimal(repaidFactor)
            balance = principal * Decimal(growth) - paidOff
        } else {
            balance = principal - installmentAmount * Decimal(periods)
        }
        return min(principal, max(.zero, balance.roundedToCurrency))
    }

    /// The outstanding principal as things stand today.
    ///
    /// Measured against the installments already charged, not the ones already
    /// paid. On a card those differ: an installment sits on the statement for
    /// weeks before the bill is cleared, and during that time the lender has
    /// still had its payment — quoting against the paid count would ask for
    /// principal the installments on the current bill are about to settle.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: What is still owed on the principal.
    func outstandingPrincipal(asOf date: Date = .now) -> Decimal {
        guard status.isRunning else { return .zero }
        return outstandingPrincipal(afterCharged: chargedCount)
    }

    /// The early-closure fee on the principal still outstanding.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: The charge, rounded to currency.
    func foreclosureCharge(asOf date: Date = .now) -> Decimal {
        guard foreclosureChargePercent > 0 else { return .zero }
        return (outstandingPrincipal(asOf: date) * foreclosureChargePercent / 100).roundedToCurrency
    }

    /// What closing the plan today would cost: the principal still owed plus the
    /// lender's fee for closing it early.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: The suggested settlement figure.
    func foreclosureQuote(asOf date: Date = .now) -> Decimal {
        (outstandingPrincipal(asOf: date) + foreclosureCharge(asOf: date)).roundedToCurrency
    }
}
