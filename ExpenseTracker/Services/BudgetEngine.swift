import Foundation

/// Where a budget stands in the period it is currently in.
struct BudgetProgress {

    /// The window these figures cover.
    let period: BudgetWindow
    /// The limit or target for one period.
    let target: Decimal
    /// How much of it the matching transactions have used up. Negative when
    /// refunds outweigh spending, which is left as-is rather than clamped so
    /// the figure still matches the transactions behind it.
    let applied: Decimal
    /// How many transactions were counted.
    let matchingCount: Int
    /// False before the budget's first period opens.
    let hasStarted: Bool
    /// True once a one-off budget's window has closed.
    let hasFinished: Bool

    /// What is still available to spend, or still to be put aside. Never below
    /// zero — going past the target is reported by `overshoot`.
    var remaining: Decimal { max(.zero, (target - applied).roundedToCurrency) }

    /// How far past the target this period went, or zero if it hasn't.
    var overshoot: Decimal { max(.zero, (applied - target).roundedToCurrency) }

    /// Share of the target used, 0...1, for the progress bar.
    var fraction: Double {
        guard target > 0 else { return 0 }
        return min(1, max(0, (applied / target).doubleValue))
    }

    /// True once the target has been reached — over the limit on an expense
    /// budget, goal met on a savings one.
    var hasReachedTarget: Bool { target > 0 && applied >= target }

    /// Whole days left in the period, counting today. Zero once it is over.
    var daysRemaining: Int {
        let today = Date.now.startOfDay
        let lastDay = period.lastMoment.startOfDay
        guard lastDay >= today else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: today, to: lastDay).day ?? 0
        return max(0, days) + 1
    }
}

/// Works out what each budget has used up. Kept out of the views so the list,
/// the editor and anything added later all read the same figures.
enum BudgetEngine {

    /// Progress for one budget over the period `date` falls in.
    /// - Parameters:
    ///   - budget: The budget to measure.
    ///   - transactions: Every transaction to consider; only matching ones in
    ///     the period are counted.
    ///   - date: Reference point; defaults to now.
    /// - Returns: The period's figures.
    static func progress(
        for budget: Budget,
        transactions: [Transaction],
        asOf date: Date = .now
    ) -> BudgetProgress {
        let period = budget.period(containing: date)
        // Stops at today rather than at the end of the period: a transaction
        // dated next week is on the app's Upcoming list and hasn't been spent
        // yet, so counting it would use the budget up before the money moved.
        let cutoff = date.endOfDay
        let matching = transactions.filter {
            $0.date <= cutoff && period.contains($0.date) && budget.includes($0)
        }
        let applied = matching
            .reduce(Decimal.zero) { $0 + budget.contribution(of: $1) }
            .roundedToCurrency
        return BudgetProgress(
            period: period,
            target: budget.amount,
            applied: applied,
            matchingCount: matching.count,
            hasStarted: budget.hasStarted(asOf: date),
            hasFinished: budget.hasFinished(asOf: date)
        )
    }
}
