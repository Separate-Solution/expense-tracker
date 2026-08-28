import Foundation
import SwiftUI

/// The two top-level buckets every transaction and category belongs to.
enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        }
    }

    /// Multiplier applied to a stored (always positive) amount.
    var sign: Decimal { self == .expense ? -1 : 1 }

    var tint: Color { self == .expense ? Theme.expense : Theme.income }

    var symbolName: String {
        self == .expense ? "arrow.up.right" : "arrow.down.left"
    }
}

enum AccountKind: String, Codable, CaseIterable, Identifiable {
    case bank
    case credit
    case cash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bank: return "Bank Account"
        case .credit: return "Credit Card"
        case .cash: return "Cash"
        }
    }

    var shortTitle: String {
        switch self {
        case .bank: return "Bank"
        case .credit: return "Credit"
        case .cash: return "Cash"
        }
    }

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

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

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

    var calendarComponent: Calendar.Component {
        switch self {
        case .daily: return .day
        case .weekly: return .weekOfYear
        case .monthly: return .month
        case .yearly: return .year
        }
    }
}
