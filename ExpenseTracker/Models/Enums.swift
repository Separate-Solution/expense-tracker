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
    case yearly

    var id: String { rawValue }

    /// Display name used in the recurrence picker.
    var title: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
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
        case .yearly: singular = "year"
        }
        return interval == 1 ? singular : "\(singular)s"
    }

    /// The `Calendar` component to step by when computing occurrences.
    var calendarComponent: Calendar.Component {
        switch self {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .yearly: return .year
        }
    }
}

/// What a transaction represents. A standard row is real spending or income; a
/// card payment moves money from a bank account to a credit card and is left out
/// of income and spending totals, because the purchases it settles were already
/// counted when they were made.
enum TransactionKind: String, Codable, CaseIterable, Identifiable {
    case standard
    case cardPayment

    var id: String { rawValue }

    /// Display name used on rows and pickers.
    var title: String {
        switch self {
        case .standard: return "Transaction"
        case .cardPayment: return "Card Payment"
        }
    }

    /// SF Symbol marking the row as a transfer rather than spending.
    var symbolName: String {
        switch self {
        case .standard: return "arrow.left.arrow.right"
        case .cardPayment: return "arrow.left.arrow.right"
        }
    }

    /// Whether this kind counts towards income and spending totals.
    var countsTowardsTotals: Bool { self == .standard }
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
