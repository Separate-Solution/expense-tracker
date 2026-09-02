import Foundation
import SwiftUI

/// The two top-level buckets every transaction and category belongs to.
enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }

    /// Display name used on pickers and section headers.
    var title: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        }
    }

    /// Multiplier applied to a stored (always positive) amount.
    var sign: Decimal { self == .expense ? -1 : 1 }

    /// Accent colour for amounts and badges of this type.
    var tint: Color { self == .expense ? Theme.expense : Theme.income }

    /// SF Symbol for the direction money moved.
    var symbolName: String {
        self == .expense ? "arrow.up.right" : "arrow.down.left"
    }
}

enum AccountKind: String, Codable, CaseIterable, Identifiable {
    case bank
    case credit
    case cash

    var id: String { rawValue }

    /// The kinds offered when creating an account. `.credit` is deliberately
    /// absent: credit cards are their own model and their own section now. The
    /// case survives so older stores and backups still decode, and so the
    /// launch migration has something to recognise.
    static let selectableCases: [AccountKind] = [.bank, .cash]

    /// True for the retired `.credit` kind, which the launch migration converts
    /// into a `CreditCard`.
    var isLegacyCreditKind: Bool { self == .credit }

    /// Full display name, used where there is room to spell it out.
    var title: String {
        switch self {
        case .bank: return "Bank Account"
        case .credit: return "Credit Card"
        case .cash: return "Cash"
        }
    }

    /// Compact name for chips and dense rows.
    var shortTitle: String {
        switch self {
        case .bank: return "Bank"
        case .credit: return "Credit"
        case .cash: return "Cash"
        }
    }

    /// Default SF Symbol for accounts of this kind.
    var symbolName: String {
        switch self {
        case .bank: return "building.columns"
        case .credit: return "creditcard"
        case .cash: return "banknote"
        }
    }

    /// Credit cards carry a balance you owe, so a positive balance is displayed as debt.
    var isLiability: Bool { self == .credit }
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    /// Display name used in the recurrence picker.
    var title: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        }
    }

    /// The unit noun for this frequency, pluralised to match `interval`.
    /// - Parameter interval: How many units each repeat spans.
    /// - Returns: E.g. "month" for 1, "months" for 3.
    func unitLabel(interval: Int) -> String {
        let singular: String
        switch self {
        case .daily: singular = "day"
        case .weekly: singular = "week"
        case .monthly: singular = "month"
        case .quarterly: singular = "quarter"
        case .yearly: singular = "year"
        }
        return interval == 1 ? singular : "\(singular)s"
    }

    /// The `Calendar` component to step by when computing occurrences.
    var calendarComponent: Calendar.Component {
        switch self {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly, .quarterly: return .month
        case .yearly: return .year
        }
    }

    /// How many `calendarComponent` steps one unit of this frequency spans.
    /// Only a quarter is worth more than one — three months.
    var stepsPerUnit: Int { self == .quarterly ? 3 : 1 }

    /// Roughly how often this comes round in a year, for normalising costs
    /// across cadences and for turning an annual interest rate into a per-period
    /// one. Weeks and days are averages, so anything built on this is an
    /// estimate rather than an exact figure.
    var periodsPerYear: Double {
        switch self {
        case .daily: return 365
        case .weekly: return 52
        case .monthly: return 12
        case .quarterly: return 4
        case .yearly: return 1
        }
    }
}

/// Where an EMI plan stands. It runs until every installment is paid, unless it
/// is closed early by paying the balance off in one go.
enum EMIStatus: String, Codable, CaseIterable, Identifiable {
    /// Still posting installments.
    case active
    /// Every installment was paid.
    case completed
    /// Closed early with a single settlement payment.
    case foreclosed

    var id: String { rawValue }

    /// Display name used on rows and section headers.
    var title: String {
        switch self {
        case .active: return "Active"
        case .completed: return "Completed"
        case .foreclosed: return "Foreclosed"
        }
    }

    /// SF Symbol for the status badge.
    var symbolName: String {
        switch self {
        case .active: return "clock"
        case .completed: return "checkmark.circle.fill"
        case .foreclosed: return "flag.checkered"
        }
    }

    /// Whether a plan in this state still posts installments.
    var isRunning: Bool { self == .active }
}

/// What a transaction represents. A standard row is real spending or income; a
/// card payment moves money from a bank account to a credit card and is left out
/// of income and spending totals, because the purchases it settles were already
/// counted when they were made.
enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case standard
    case cardPayment
    /// Money moved between two of your own accounts. Like a card payment it is
    /// not spending — nothing left your pocket, it just sits somewhere else.
    case transfer

    var id: String { rawValue }

    /// Display name used on rows and pickers.
    var title: String {
        switch self {
        case .standard: return "Transaction"
        case .cardPayment: return "Card Payment"
        case .transfer: return "Transfer"
        }
    }

    /// SF Symbol marking the row as a movement rather than spending.
    var symbolName: String { "arrow.left.arrow.right" }

    /// Whether this kind counts towards income and spending totals. Only real
    /// spending and income do; the two movement kinds are between your own
    /// pockets, and counting them would double up money already recorded.
    var countsTowardsTotals: Bool { self == .standard }

    /// Whether this kind moves money between two places you own, so it needs
    /// both ends set and is barred from carrying a category.
    var isMovement: Bool { self != .standard }
}

/// Where a transaction's money came from — a bank account or a credit card.
/// Used by the pickers, which have to offer both in one list.
enum PaymentSource: Hashable, Identifiable {
    case account(UUID)
    case creditCard(UUID)

    var id: String {
        switch self {
        case .account(let id): return "account-\(id.uuidString)"
        case .creditCard(let id): return "card-\(id.uuidString)"
        }
    }
}

/// What a budget is trying to do. An expense budget caps what may go out; a
/// savings budget sets a target to put aside. The two run the same maths in
/// opposite directions, so one model covers both.
enum BudgetKind: String, Codable, CaseIterable, Identifiable {
    case expense
    case savings

    var id: String { rawValue }

    /// Display name used on the type switch and section headers.
    var title: String {
        switch self {
        case .expense: return "Expense"
        case .savings: return "Savings"
        }
    }

    /// Verb for what has been counted so far — "Spent" against a limit,
    /// "Saved" towards a target.
    var appliedLabel: String {
        switch self {
        case .expense: return "Spent"
        case .savings: return "Saved"
        }
    }

    /// What the untouched part of the budget is called.
    var remainingLabel: String {
        switch self {
        case .expense: return "left"
        case .savings: return "to go"
        }
    }

    /// What the amount field means for this kind.
    var amountLabel: String {
        switch self {
        case .expense: return "Limit"
        case .savings: return "Target"
        }
    }

    /// SF Symbol for the budget's badge.
    var symbolName: String {
        switch self {
        case .expense: return "chart.pie"
        case .savings: return "banknote"
        }
    }

    /// Which direction of money counts towards the budget. An expense budget
    /// fills up as money goes out and is brought back down by a refund; a
    /// savings budget fills up as money comes in.
    var countingSign: Decimal { self == .savings ? 1 : -1 }

    /// The scope a new budget of this kind starts with.
    var defaultScope: BudgetScope { self == .savings ? .allIncome : .allExpenses }
}

/// The window a budget's amount applies to — "₹500 per 2 weeks". `.custom` is
/// the odd one out: it is a single stretch between two dates that never
/// repeats, for a trip or a one-off project.
enum BudgetPeriod: String, Codable, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year
    case custom

    var id: String { rawValue }

    /// Display name used in the period picker.
    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        case .custom: return "Custom"
        }
    }

    /// The unit noun, pluralised to match `interval`.
    /// - Parameter interval: How many units each period spans.
    /// - Returns: E.g. "month" for 1, "months" for 3.
    func unitLabel(interval: Int) -> String {
        let singular: String
        switch self {
        case .day: singular = "day"
        case .week: singular = "week"
        case .month: singular = "month"
        case .year: singular = "year"
        case .custom: return "custom period"
        }
        return interval == 1 ? singular : "\(singular)s"
    }

    /// The `Calendar` component periods step by; nil for `.custom`, which does
    /// not step at all.
    var calendarComponent: Calendar.Component? {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        case .custom: return nil
        }
    }

    /// Whether the period rolls over into a fresh one when it ends.
    var isRepeating: Bool { self != .custom }
}

/// Which transactions a budget counts. Categories a budget excludes are taken
/// out of whichever of these is chosen.
enum BudgetScope: String, Codable, CaseIterable, Identifiable {
    /// Every expense in range.
    case allExpenses
    /// Every income row in range.
    case allIncome
    /// Both directions, netted against each other.
    case everything
    /// Only the categories picked by hand.
    case categories

    var id: String { rawValue }

    /// Display name used in the "counts" picker.
    var title: String {
        switch self {
        case .allExpenses: return "All expenses"
        case .allIncome: return "All income"
        case .everything: return "Income and expenses"
        case .categories: return "Chosen categories"
        }
    }

    /// One line saying what this scope pulls in, for the picker's footer.
    var explanation: String {
        switch self {
        case .allExpenses:
            return "Every expense in the period counts. Refunds bring the total back down."
        case .allIncome:
            return "Every income transaction in the period counts."
        case .everything:
            return "Income and expenses are netted against each other."
        case .categories:
            return "Only transactions in the categories you pick count."
        }
    }

    /// Whether this scope needs a hand-picked category list.
    var needsCategorySelection: Bool { self == .categories }
}
