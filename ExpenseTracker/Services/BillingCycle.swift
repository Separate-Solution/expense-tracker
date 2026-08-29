import Foundation

/// One statement period on a credit card: the window charges fall into, the day
/// it closes, and the day the resulting bill has to be paid.
struct BillingCycle: Equatable {
    /// Midnight on the first day covered by the statement.
    let start: Date
    /// The last moment of the statement day — charges up to here are on this bill.
    let end: Date
    /// The last moment of the day the bill is due.
    let dueDate: Date

    /// Whether a transaction date falls inside this statement period.
    /// - Parameter date: The date to test.
    /// - Returns: True when the charge belongs on this statement.
    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }

    /// Whole days from `date` until the bill is due; negative once it is overdue.
    ///
    /// Takes the reference date rather than reading the clock, so a cycle built
    /// for some other day is measured against that day too.
    /// - Parameter date: The day to count from; defaults to today.
    /// - Returns: Days remaining, negative once overdue.
    func daysUntilDue(asOf date: Date = .now) -> Int {
        Calendar.current.dateComponents(
            [.day],
            from: date.startOfDay,
            to: dueDate.startOfDay
        ).day ?? 0
    }

    /// Whether the due date has passed.
    /// - Parameter date: The day to judge from; defaults to today.
    /// - Returns: True once the bill is late.
    func isOverdue(asOf date: Date = .now) -> Bool {
        date.startOfDay > dueDate.startOfDay
    }

    // MARK: - Construction

    /// Keeps a stored day-of-month inside a range every calendar month can be
    /// mapped onto. 31 is allowed and clamped per month when a date is built.
    /// - Parameter day: The raw day value.
    /// - Returns: The value clamped to 1...31.
    static func clampDayOfMonth(_ day: Int) -> Int {
        min(31, max(1, day))
    }

    /// The given day of the month `reference` falls in, clamped to that month's
    /// length so day 31 lands on the 28th in February rather than spilling over.
    /// - Parameters:
    ///   - day: Desired day of the month.
    ///   - reference: Any date inside the target month.
    /// - Returns: Midnight on the resolved day.
    static func date(day: Int, inMonthOf reference: Date) -> Date {
        let calendar = Calendar.current
        let startOfMonth = reference.startOfMonth
        let length = calendar.range(of: .day, in: .month, for: startOfMonth)?.count ?? 28
        let resolved = min(clampDayOfMonth(day), length)
        return calendar.date(
            byAdding: DateComponents(day: resolved - 1),
            to: startOfMonth
        ) ?? startOfMonth
    }

    /// The statement period that most recently closed on or before `date`.
    ///
    /// A statement closing on the 5th covers the 6th of the previous month
    /// through the 5th of this one. On the 5th itself the cycle has just closed,
    /// so that day's statement is the one returned.
    /// - Parameters:
    ///   - statementDay: Day of the month the statement closes.
    ///   - dueDay: Day of the month the bill is due.
    ///   - date: Reference point; defaults to now.
    /// - Returns: The closed cycle.
    static func lastClosed(statementDay: Int, dueDay: Int, asOf date: Date = .now) -> BillingCycle {
        let thisMonthClose = self.date(day: statementDay, inMonthOf: date).endOfDay
        let close = thisMonthClose <= date
            ? thisMonthClose
            : self.date(day: statementDay, inMonthOf: date.addingMonths(-1)).endOfDay

        return cycle(closingAt: close, statementDay: statementDay, dueDay: dueDay)
    }

    /// The period charges are landing in right now — the one that closes next.
    /// - Parameters:
    ///   - statementDay: Day of the month the statement closes.
    ///   - dueDay: Day of the month the bill is due.
    ///   - date: Reference point; defaults to now.
    /// - Returns: The open cycle.
    static func current(statementDay: Int, dueDay: Int, asOf date: Date = .now) -> BillingCycle {
        let previous = lastClosed(statementDay: statementDay, dueDay: dueDay, asOf: date)
        let close = self.date(day: statementDay, inMonthOf: previous.end.addingMonths(1)).endOfDay
        return cycle(closingAt: close, statementDay: statementDay, dueDay: dueDay)
    }

    /// Builds the window and due date around a known statement close.
    ///
    /// The bill falls due in the same month when the due day is later than the
    /// statement day, and in the following month otherwise — a statement closing
    /// on the 25th with payment due on the 12th is due the 12th of next month.
    /// - Parameters:
    ///   - close: The last moment of the statement day.
    ///   - statementDay: Day of the month the statement closes.
    ///   - dueDay: Day of the month the bill is due.
    /// - Returns: The assembled cycle.
    private static func cycle(closingAt close: Date, statementDay: Int, dueDay: Int) -> BillingCycle {
        let previousClose = date(day: statementDay, inMonthOf: close.addingMonths(-1)).endOfDay
        // The day after the previous statement closed is the first day billed here.
        let start = (Calendar.current.date(byAdding: .day, value: 1, to: previousClose.startOfDay)
            ?? previousClose).startOfDay

        let dueMonth = clampDayOfMonth(dueDay) > clampDayOfMonth(statementDay)
            ? close
            : close.addingMonths(1)

        return BillingCycle(
            start: start,
            end: close,
            dueDate: date(day: dueDay, inMonthOf: dueMonth).endOfDay
        )
    }
}
