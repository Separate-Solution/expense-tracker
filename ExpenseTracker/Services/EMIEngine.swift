import Foundation
import SwiftData

/// Keeps EMI plans in step with reality: posts the installments that have fallen
/// due, notices when the last one has actually been paid, and closes a plan
/// early when it is settled in one go.
///
/// Runs on launch and on foreground alongside the recurrence engine, and again
/// after a credit card bill is paid — an installment charged to a card is only
/// paid once the statement carrying it is cleared, so settling a bill can be
/// what finishes a plan.
enum EMIEngine {

    /// Creates any installment a plan says should already exist by `date`, then
    /// closes the plans whose installments are all paid.
    /// - Parameters:
    ///   - context: The store to post into.
    ///   - date: Reference point; defaults to now.
    /// - Returns: How many installments were created.
    @discardableResult
    static func postDueInstallments(in context: ModelContext, asOf date: Date = .now) -> Int {
        let descriptor = FetchDescriptor<EMIPlan>()
        guard let plans = try? context.fetch(descriptor) else { return 0 }

        var created = 0
        for plan in plans where plan.status.isRunning {
            for index in plan.pendingIndexes(upTo: date) {
                guard let due = plan.installmentDate(at: index) else { continue }
                let installment = Transaction(
                    title: plan.title,
                    amount: plan.installmentAmount,
                    type: .expense,
                    date: due,
                    note: plan.note,
                    account: plan.account,
                    creditCard: plan.creditCard,
                    category: plan.category,
                    emiPlan: plan,
                    emiInstallmentIndex: index
                )
                context.insert(installment)
                plan.lastPostedIndex = index
                created += 1
            }
        }

        let closed = closeFinishedPlans(plans, asOf: date)

        if created > 0 || closed > 0 {
            try? context.save()
        }
        return created
    }

    /// Closes every plan whose installments have all been paid, without posting
    /// anything. This is the half that a card bill payment can change: the
    /// installments were charged long ago, and clearing the statement is what
    /// finally pays them.
    /// - Parameters:
    ///   - context: The store to check.
    ///   - date: Reference point; defaults to now.
    /// - Returns: How many plans were completed.
    @discardableResult
    static func refreshCompletions(in context: ModelContext, asOf date: Date = .now) -> Int {
        let descriptor = FetchDescriptor<EMIPlan>()
        guard let plans = try? context.fetch(descriptor) else { return 0 }
        let closed = closeFinishedPlans(plans, asOf: date)
        if closed > 0 {
            try? context.save()
        }
        return closed
    }

    /// Marks the plans that have nothing left to pay as completed. A plan is
    /// only finished once every installment has posted *and* been paid, so one
    /// charged to a card waits for the bill that carries its last installment.
    /// - Parameters:
    ///   - plans: The plans to judge.
    ///   - date: Reference point.
    /// - Returns: How many were closed.
    @discardableResult
    private static func closeFinishedPlans(_ plans: [EMIPlan], asOf date: Date) -> Int {
        var closed = 0
        for plan in plans where plan.status.isRunning {
            guard plan.lastPostedIndex >= plan.installmentCount - 1,
                  plan.paidCount(asOf: date) >= plan.installmentCount else { continue }
            plan.status = .completed
            // Dated by the last installment rather than today, so a plan that
            // finished while the app was closed doesn't claim it ended the day
            // it was next opened.
            plan.closedDate = plan.installments.last?.date ?? date
            closed += 1
        }
        return closed
    }

    /// Closes a plan early with one settlement payment.
    ///
    /// The payment is an ordinary expense on whatever the installments were
    /// charged to, so it leaves a bank account the same way an installment
    /// would, and lands on the card's next bill when the plan was on a card.
    /// - Parameters:
    ///   - plan: The plan being closed.
    ///   - amount: What was actually paid to close it; the magnitude is used.
    ///   - date: When the payment was made; defaults to now.
    ///   - context: Context to insert into.
    /// - Returns: The settlement transaction, or nil for a non-positive amount.
    /// - Throws: Any error from saving, so a failed foreclosure isn't reported
    ///   as a success by the sheet that asked for it.
    @discardableResult
    static func foreclose(
        _ plan: EMIPlan,
        amount: Decimal,
        date: Date = .now,
        in context: ModelContext
    ) throws -> Transaction? {
        let value = abs(amount).roundedToCurrency
        guard value > 0 else { return nil }

        let payment = Transaction(
            title: "Foreclosure · \(plan.title)",
            amount: value,
            type: .expense,
            date: date,
            note: plan.note,
            account: plan.account,
            creditCard: plan.creditCard,
            category: plan.category,
            emiPlan: plan
        )
        context.insert(payment)

        plan.closingPaymentID = payment.id
        plan.status = .foreclosed
        plan.closedDate = date
        // Nothing more should post: the balance the remaining installments were
        // going to collect has just been paid off in one go.
        plan.lastPostedIndex = plan.installmentCount - 1

        // Rolls the insert back on failure, so a foreclosure the sheet is about
        // to report as failed can't be left pending for the next save to commit.
        if let failure = context.saveReportingFailure() {
            throw failure
        }
        return payment
    }

    /// Reopens a foreclosed plan — undoing a settlement made by mistake. The
    /// settlement transaction is removed and posting resumes from the last
    /// installment that actually exists.
    /// - Parameters:
    ///   - plan: The plan to reopen.
    ///   - context: Context to delete from.
    static func reopen(_ plan: EMIPlan, in context: ModelContext) {
        if let payment = plan.closingPayment {
            context.delete(payment)
        }
        plan.closingPaymentID = nil
        plan.status = .active
        plan.closedDate = nil
        // Taken from the indexes the installments carry rather than from how
        // many there are: the settlement payment carries none, so a delete that
        // has not been processed yet cannot inflate the count and make the
        // engine skip the next installment.
        plan.lastPostedIndex = lastIndex(of: plan)
    }

    /// Rewrites installments that haven't fallen due yet after a plan is edited,
    /// leaving what has already posted alone — the same rule the recurrence
    /// engine follows, so history is never rewritten under the user.
    /// - Parameters:
    ///   - plan: The edited plan.
    ///   - context: Context to delete from.
    ///   - date: Reference point; defaults to now.
    static func applyEdits(of plan: EMIPlan, in context: ModelContext, asOf date: Date = .now) {
        let cutoff = date.endOfDay
        var remaining = plan.installments
        // A shortened plan can leave installments beyond its new end, which are
        // no longer part of it however long ago they posted.
        for installment in plan.installments
        where installment.date > cutoff || (installment.emiInstallmentIndex ?? 0) >= plan.installmentCount {
            context.delete(installment)
            remaining.removeAll { $0.id == installment.id }
        }
        // Rebuilt from the highest index left rather than from how many are
        // left: a plan that skipped the installments already due when it was
        // created has fewer rows than indexes covered.
        plan.lastPostedIndex = lastIndex(of: plan, among: remaining)
    }

    /// The highest installment index a plan has actually posted, or -1 when it
    /// has posted none.
    /// - Parameters:
    ///   - plan: The plan to measure.
    ///   - installments: The rows to read; the plan's own by default.
    /// - Returns: The index the schedule has reached.
    private static func lastIndex(of plan: EMIPlan, among installments: [Transaction]? = nil) -> Int {
        let rows = installments ?? plan.installments
        let highest = rows.compactMap(\.emiInstallmentIndex).max() ?? -1
        return min(highest, plan.installmentCount - 1)
    }
}
