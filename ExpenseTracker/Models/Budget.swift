import Foundation
import SwiftData

/// A spending limit or a savings target measured over a repeating window.
///
/// A budget doesn't hold money of its own — it watches the transactions that
/// already exist and reports how much of the period's amount they have used up.
/// Which ones it watches is the `scope`, narrowed by `excludedCategories` and,
/// when any are chosen, by the accounts and cards it is tied to.
@Model
final class Budget {

    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = BudgetKind.expense.rawValue
    /// The limit (expense) or target (savings) for one period. Always positive.
    var amount: Decimal = Decimal.zero
    var periodRaw: String = BudgetPeriod.month.rawValue
    /// How many units of `period` one window spans — 2 + `.week` is fortnightly.
    /// Ignored by `.custom`, which runs once between two dates.
    var periodInterval: Int = 1
    /// First day the budget covers; every later period is measured from here.
    var startDate: Date = Date()
    /// Last day covered by a `.custom` period. Unused by the repeating ones.
    var endDate: Date?
    var scopeRaw: String = BudgetScope.allExpenses.rawValue
    var colorHex: String = Theme.paletteHexes[0]
    var isArchived: Bool = false
    var sortIndex: Int = 0
    var note: String = ""
    var createdAt: Date = Date()

    /// Categories counted when `scope` is `.categories`. Empty means nothing
    /// matches yet, which the editor warns about rather than silently counting
    /// everything.
    @Relationship(deleteRule: .nullify, inverse: \Category.includingBudgets)
    var includedCategories: [Category]? = []

    /// Categories left out whatever the scope says — the rent you don't want
    /// counted against a day-to-day spending budget.
    @Relationship(deleteRule: .nullify, inverse: \Category.excludingBudgets)
    var excludedCategories: [Category]? = []

    /// Bank accounts the budget watches. Empty means every account.
    @Relationship(deleteRule: .nullify, inverse: \Account.budgets)
    var accounts: [Account]? = []

    /// Credit cards the budget watches. Empty means every card.
    @Relationship(deleteRule: .nullify, inverse: \CreditCard.budgets)
    var creditCards: [CreditCard]? = []

    /// Creates a budget.
    /// - Parameters:
    ///   - id: Stable identifier; a fresh UUID unless restoring from a backup.
    ///   - name: Display name.
    ///   - kind: Spending limit or savings target.
    ///   - amount: Magnitude for one period; the absolute value is stored.
    ///   - period: Day, week, month, year, or a one-off custom window.
    ///   - periodInterval: Units per period; clamped to at least 1.
    ///   - startDate: First day covered, snapped to the start of that day.
    ///   - endDate: Last day of a `.custom` window, snapped to the end of that day.
    ///   - scope: Which transactions count towards it.
    ///   - colorHex: Accent colour; defaults to the first palette entry.
    ///   - sortIndex: Position in the budgets list.
    ///   - note: Free-text note.
    ///   - createdAt: Creation timestamp.
    init(
        id: UUID = UUID(),
        name: String,
        kind: BudgetKind = .expense,
        amount: Decimal,
        period: BudgetPeriod = .month,
        periodInterval: Int = 1,
        startDate: Date = Date(),
        endDate: Date? = nil,
        scope: BudgetScope = .allExpenses,
        colorHex: String = Theme.paletteHexes[0],
        sortIndex: Int = 0,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.amount = abs(amount)
        self.periodRaw = period.rawValue
        self.periodInterval = max(1, periodInterval)
        self.startDate = startDate.startOfDay
        self.endDate = endDate?.endOfDay
        self.scopeRaw = scope.rawValue
        self.colorHex = colorHex
        self.isArchived = false
        self.sortIndex = sortIndex
        self.note = note
        self.createdAt = createdAt
    }

    // MARK: - Typed views

    /// Typed view of `kindRaw`; falls back to `.expense` on an unknown value.
    var kind: BudgetKind {
        get { BudgetKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    /// Typed view of `periodRaw`; falls back to `.month` on an unknown value.
    var period: BudgetPeriod {
        get { BudgetPeriod(rawValue: periodRaw) ?? .month }
        set { periodRaw = newValue.rawValue }
    }

    /// Typed view of `scopeRaw`; falls back to `.allExpenses` on an unknown value.
    var scope: BudgetScope {
        get { BudgetScope(rawValue: scopeRaw) ?? .allExpenses }
        set { scopeRaw = newValue.rawValue }
    }

    /// Cadence in words, e.g. "₹500 every 2 weeks" without the amount.
    var periodSummary: String {
        guard period.isRepeating else { return "One-off period" }
        return periodInterval == 1
            ? "Every \(period.unitLabel(interval: 1))"
            : "Every \(periodInterval) \(period.unitLabel(interval: periodInterval))"
    }

    // MARK: - Periods

    /// The dates alone, so the editor can work out the window a not-yet-saved
    /// budget would have without building a model object to ask.
    var schedule: BudgetSchedule {
        BudgetSchedule(
            period: period,
            interval: periodInterval,
            startDate: startDate,
            endDate: endDate
        )
    }

    /// The period `date` falls in.
    /// - Parameter date: The day to locate; defaults to now.
    /// - Returns: The window it belongs to.
    func period(containing date: Date = .now) -> BudgetWindow {
        schedule.period(containing: date)
    }

    /// True once the budget's first period has opened.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: Whether the budget is counting yet.
    func hasStarted(asOf date: Date = .now) -> Bool { date >= startDate.startOfDay }

    /// True when a custom window has closed for good. Repeating budgets never
    /// finish.
    /// - Parameter date: Reference point; defaults to now.
    /// - Returns: Whether there is nothing left to count.
    func hasFinished(asOf date: Date = .now) -> Bool {
        guard !period.isRepeating, let endDate else { return false }
        return date > endDate
    }

    // MARK: - Matching

    /// Whether a transaction is counted by this budget.
    ///
    /// Movements between your own pockets never count — a card payment or a
    /// transfer settles or relocates money that was already counted when it was
    /// spent, so counting it again would use the budget up twice.
    /// - Parameter transaction: The row to test.
    /// - Returns: True when it counts towards this budget.
    func includes(_ transaction: Transaction) -> Bool {
        guard transaction.countsTowardsTotals else { return false }

        if let category = transaction.category,
           (excludedCategories ?? []).contains(where: { $0.id == category.id }) {
            return false
        }

        switch scope {
        case .allExpenses:
            guard transaction.type == .expense else { return false }
        case .allIncome:
            guard transaction.type == .income else { return false }
        case .everything:
            break
        case .categories:
            guard let category = transaction.category,
                  (includedCategories ?? []).contains(where: { $0.id == category.id })
            else { return false }
        }

        return matchesSelectedSources(transaction)
    }

    /// Whether the row moved through one of the accounts or cards this budget
    /// watches. A budget tied to nothing watches everything.
    /// - Parameter transaction: The row to test.
    /// - Returns: True when the row's source is in scope.
    private func matchesSelectedSources(_ transaction: Transaction) -> Bool {
        let accountIDs = (accounts ?? []).map(\.id)
        let cardIDs = (creditCards ?? []).map(\.id)
        guard !accountIDs.isEmpty || !cardIDs.isEmpty else { return true }
        return accountIDs.contains { transaction.involves(.account($0)) }
            || cardIDs.contains { transaction.involves(.creditCard($0)) }
    }

    /// What a matching transaction does to the budget's progress. An expense
    /// budget is filled by money going out and unwound by a refund; a savings
    /// budget the other way round.
    /// - Parameter transaction: The row to weigh.
    /// - Returns: A positive amount when it uses the budget up.
    func contribution(of transaction: Transaction) -> Decimal {
        transaction.signedAmount * kind.countingSign
    }
}

/// One budget period: open at the start, closed just before the next one opens.
///
/// The end is deliberately exclusive. Writing it as "one second before the next
/// period" would drop a transaction stamped in the fraction of a second between
/// the two — `Date()` keeps sub-second precision, so that gap is reachable.
struct BudgetWindow {

    /// First moment the period covers.
    let start: Date
    /// First moment it no longer covers — the next period's start.
    let end: Date

    /// Whether the period covers `date`.
    /// - Parameter date: The moment to test.
    /// - Returns: True when it falls in this window.
    func contains(_ date: Date) -> Bool { date >= start && date < end }

    /// The last moment the period covers, for showing the window to the reader
    /// — "30 Aug \u{2013} 29 Sep" rather than a range ending on the 30th.
    var lastMoment: Date { max(start, end.addingTimeInterval(-1)) }
}

/// A budget's timing, apart from the budget itself: where its periods start and
/// how long each one runs. Split out so the editor can preview the window a
/// budget *would* have before anything is saved.
struct BudgetSchedule {

    let period: BudgetPeriod
    /// Units of `period` per window; treated as at least 1.
    let interval: Int
    let startDate: Date
    /// Last day of a `.custom` window; unused by the repeating periods.
    let endDate: Date?

    /// Units per period, never below one.
    private var step: Int { max(1, interval) }

    /// Start of the nth period, always measured from `startDate` so months never
    /// drift — one starting on the 31st lands on the 28th in February and back
    /// on the 31st in March.
    /// - Parameter index: Zero-based period number.
    /// - Returns: The day that period opens, or nil for a custom window past 0.
    func periodStart(at index: Int) -> Date? {
        guard index >= 0 else { return nil }
        guard index > 0 else { return startDate.startOfDay }
        guard let component = period.calendarComponent else { return nil }
        return Calendar.current.date(
            byAdding: component,
            value: index * step,
            to: startDate.startOfDay
        )
    }

    /// The period `date` falls in — the first period when the budget hasn't
    /// begun yet, and the last one when a custom window has already closed.
    /// - Parameter date: The day to locate; defaults to now.
    /// - Returns: The window it belongs to.
    func period(containing date: Date = .now) -> BudgetWindow {
        let opening = startDate.startOfDay
        guard period.isRepeating else {
            // A custom window with no end date is open-ended; a year gives the
            // progress bar something finite to measure against. The window runs
            // to the end of its last day, so the exclusive end is the midnight
            // that follows.
            let lastDay = (endDate ?? opening.addingMonths(12)).startOfDay
            let close = Calendar.current.date(byAdding: DateComponents(day: 1), to: lastDay)
                ?? lastDay
            return BudgetWindow(start: opening, end: max(opening, close))
        }
        let index = periodIndex(containing: date)
        let start = periodStart(at: index) ?? opening
        guard let nextStart = periodStart(at: index + 1) else {
            return BudgetWindow(start: start, end: start.endOfDay)
        }
        return BudgetWindow(start: start, end: nextStart)
    }

    /// Which period `date` falls in.
    ///
    /// The index is worked out arithmetically rather than by stepping one period
    /// at a time: a daily budget running for years would otherwise cost
    /// thousands of calendar calls every time a row is drawn. Calendars clamp
    /// and skip — a month-end start, a DST change — so the estimate is nudged
    /// into place afterwards, which takes a step or two at most.
    /// - Parameter date: The day to locate.
    /// - Returns: The zero-based period number, never below zero.
    private func periodIndex(containing date: Date) -> Int {
        let calendar = Calendar.current
        let opening = startDate.startOfDay
        guard date > opening else { return 0 }

        let elapsed: Int
        switch period {
        case .day:
            elapsed = calendar.dateComponents([.day], from: opening, to: date).day ?? 0
        case .week:
            elapsed = (calendar.dateComponents([.day], from: opening, to: date).day ?? 0) / 7
        case .month:
            elapsed = calendar.dateComponents([.month], from: opening, to: date).month ?? 0
        case .year:
            elapsed = calendar.dateComponents([.year], from: opening, to: date).year ?? 0
        case .custom:
            return 0
        }

        var index = max(0, elapsed / step)
        // Both corrections are bounded: the estimate is never more than a period
        // or two out, and each loop only runs while it is.
        while index > 0, let current = periodStart(at: index), current > date {
            index -= 1
        }
        while let next = periodStart(at: index + 1), next <= date {
            index += 1
        }
        return index
    }
}
