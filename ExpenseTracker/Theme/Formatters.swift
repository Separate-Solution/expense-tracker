import Foundation
import SwiftUI

enum Formatters {

    /// Currency code the whole app formats with. Stored in UserDefaults so
    /// Settings can change it without touching stored data.
    static var currencyCode: String {
        UserDefaults.standard.string(forKey: SettingsKey.currencyCode)
            ?? Locale.current.currency?.identifier
            ?? "USD"
    }

    /// Whole amounts read better without ".00", but a value with paise must show
    /// both digits — never one, which is what an open 0...2 range would produce.
    private static func fractionDigits(for value: Decimal) -> Int {
        let rounded = value.roundedToCurrency
        var source = rounded
        var whole = Decimal()
        NSDecimalRound(&whole, &source, 0, .down)
        return rounded == whole ? 0 : 2
    }

    /// Formats an amount in the app's currency.
    /// - Parameters:
    ///   - value: The amount; rounded to 2 places first.
    ///   - showsSign: When true, prefixes positive values with "+".
    /// - Returns: The formatted string, e.g. "₹1,299" or "+₹1,299.50".
    static func currency(_ value: Decimal, showsSign: Bool = false) -> String {
        let rounded = value.roundedToCurrency
        let formatted = rounded.formatted(
            .currency(code: currencyCode).precision(.fractionLength(fractionDigits(for: rounded)))
        )
        guard showsSign, rounded > 0 else { return formatted }
        return "+" + formatted
    }

    /// Magnitude only — used where a coloured +/- prefix is drawn separately.
    static func currencyMagnitude(_ value: Decimal) -> String {
        let rounded = abs(value).roundedToCurrency
        return rounded.formatted(
            .currency(code: currencyCode).precision(.fractionLength(fractionDigits(for: rounded)))
        )
    }

    /// Formats an amount with an explicit +/− prefix, using a typographic minus.
    /// - Parameter value: The amount; zero is returned unsigned.
    /// - Returns: The signed, formatted string.
    static func signedCurrency(_ value: Decimal) -> String {
        let magnitude = currencyMagnitude(value)
        if value < 0 { return "−" + magnitude }
        if value > 0 { return "+" + magnitude }
        return magnitude
    }

    static let dayHeader: Date.FormatStyle = .dateTime.weekday(.wide).day().month(.abbreviated)
    static let shortDate: Date.FormatStyle = .dateTime.day().month(.abbreviated).year()
    static let monthTitle: Date.FormatStyle = .dateTime.month(.wide).year()

    /// "Today" / "Yesterday" / "Tomorrow", otherwise a full date.
    static func relativeDayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(dayHeader)
    }
}

extension Date {
    /// Midnight at the start of this date, in the current calendar.
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    /// The last second of this date — the inclusive upper bound for "today".
    var endOfDay: Date {
        Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? self
    }

    /// Midnight on the first day of this date's month.
    var startOfMonth: Date {
        let components = Calendar.current.dateComponents([.year, .month], from: self)
        return Calendar.current.date(from: components) ?? startOfDay
    }

    /// The last second of this date's month.
    var endOfMonth: Date {
        let next = Calendar.current.date(byAdding: DateComponents(month: 1), to: startOfMonth) ?? self
        return Calendar.current.date(byAdding: DateComponents(second: -1), to: next) ?? self
    }

    /// Shifts the date by whole months, clamping to valid days.
    /// - Parameter count: Months to add; negative moves backwards.
    /// - Returns: The shifted date, or self if the calendar cannot produce one.
    func addingMonths(_ count: Int) -> Date {
        Calendar.current.date(byAdding: DateComponents(month: count), to: self) ?? self
    }
}

extension Decimal {
    /// Lossy `Double` view, used only for chart geometry — never for money maths.
    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }

    /// Rounds to 2 decimal places — applied before anything is persisted.
    var roundedToCurrency: Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, 2, .plain)
        return result
    }
}

enum SettingsKey {
    static let currencyCode = "settings.currencyCode"
    static let appearance = "settings.appearance"
    static let defaultAccountID = "settings.defaultAccountID"
    static let didSeedDefaults = "settings.didSeedDefaults"
}

extension Character {
    /// True for characters that actually render as emoji, used when deciding
    /// whether an imported "emoji" column holds a real glyph.
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation
            || (scalar.properties.isEmoji && unicodeScalars.count > 1)
    }
}
