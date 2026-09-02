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

    /// A balance: the magnitude, with a minus only when it is negative. Unlike
    /// `signedCurrency` there is no "+" on positives — a plus reads as a
    /// change, and a balance is a standing amount rather than a movement.
    /// - Parameter value: The balance to format.
    /// - Returns: The formatted balance.
    static func balance(_ value: Decimal) -> String {
        let magnitude = currencyMagnitude(value)
        return value < 0 ? "\u{2212}" + magnitude : magnitude
    }

    /// A day of the month as an ordinal — "1st", "22nd", "31st" — used for the
    /// statement and due days on a credit card.
    /// - Parameter day: Day of the month, 1...31.
    /// - Returns: The ordinal string, falling back to the bare number.
    static func ordinalDay(_ day: Int) -> String {
        ordinalFormatter.string(from: NSNumber(value: day)) ?? "\(day)"
    }

    /// A percentage, trimmed of a pointless ".0" — "13.5%", "0%", "18%".
    /// - Parameter value: The rate as a percentage, not a fraction.
    /// - Returns: The formatted string.
    static func percent(_ value: Decimal) -> String {
        let rounded = value.roundedToCurrency
        var source = rounded
        var whole = Decimal()
        NSDecimalRound(&whole, &source, 0, .down)
        let digits = rounded == whole ? 0 : 2
        return rounded.formatted(.number.precision(.fractionLength(digits))) + "%"
    }

    private static let ordinalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()

    static let dayHeader: Date.FormatStyle = .dateTime.weekday(.wide).day().month(.abbreviated)
    static let shortDate: Date.FormatStyle = .dateTime.day().month(.abbreviated).year()
    static let monthTitle: Date.FormatStyle = .dateTime.month(.wide).year()
    /// Time of day, in the reader's 12/24-hour preference.
    static let timeOfDay: Date.FormatStyle = .dateTime.hour().minute()
    static let dateAndTime: Date.FormatStyle = .dateTime.day().month(.abbreviated).year().hour().minute()

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
    /// Reads a small number typed into a field — a rate, a percentage — in
    /// whatever form the reader's keypad produces it.
    ///
    /// The numeric keypad emits the device locale's decimal separator, which is
    /// a comma across much of Europe. `Decimal(string:)` reads only the plain
    /// form, and it does not fail on the rest — it stops at the first mark it
    /// doesn't recognise, so "13,5" comes back as 13 and the fraction is
    /// silently dropped.
    ///
    /// Both marks are read as the decimal point rather than one of them being
    /// treated as grouping, which is only safe because these fields hold
    /// percentages: nobody groups a rate, so "1,234" can only mean 1.234. An
    /// amount would need the locale's own rules — those go through the
    /// calculator keypad, which never sees typed text.
    /// - Parameter percentInput: The raw text from the field.
    /// - Returns: The value, or nil when the text isn't a number.
    init?(percentInput: String) {
        let cleaned = percentInput
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        self = value
    }

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
