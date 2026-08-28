import Foundation

enum CalcOperator: String, CaseIterable {
    case add, subtract, multiply, divide

    var symbol: String {
        switch self {
        case .add: return "+"
        case .subtract: return "−"
        case .multiply: return "×"
        case .divide: return "÷"
        }
    }

    var precedence: Int { (self == .multiply || self == .divide) ? 2 : 1 }
}

/// Left-to-right expression builder with ×/÷ precedence, used by the amount keypad.
/// Holds completed operands separately from the number currently being typed so
/// backspace and operator-replacement behave the way a phone calculator does.
struct CalculatorEngine {

    private(set) var operands: [Decimal] = []
    private(set) var operators: [CalcOperator] = []
    private(set) var entry: String = ""

    private let maxIntegerDigits = 12
    private let maxFractionDigits = 2

    // MARK: - Queries

    var isEmpty: Bool { operands.isEmpty && entry.isEmpty }

    /// True once there is arithmetic to show a running total for.
    var hasExpression: Bool { !operators.isEmpty }

    var displayText: String {
        var parts: [String] = []
        for (index, value) in operands.enumerated() {
            parts.append(Self.format(value))
            if index < operators.count { parts.append(operators[index].symbol) }
        }
        if !entry.isEmpty {
            parts.append(entry)
        } else if operands.isEmpty {
            parts.append("0")
        }
        return parts.joined(separator: " ")
    }

    /// Evaluated value, or nil if the expression cannot be resolved (e.g. ÷ 0).
    var result: Decimal? {
        var values = operands
        if let typed = Self.parse(entry) {
            values.append(typed)
        }
        guard !values.isEmpty else { return .zero }

        var ops = operators
        // A trailing operator with nothing after it is ignored while evaluating.
        while ops.count >= values.count { ops.removeLast() }

        // Pass 1: × and ÷.
        var reducedValues: [Decimal] = [values[0]]
        var reducedOps: [CalcOperator] = []
        for (index, op) in ops.enumerated() {
            let rhs = values[index + 1]
            if op.precedence == 2 {
                guard let lhs = reducedValues.popLast() else { return nil }
                if op == .divide {
                    guard rhs != 0 else { return nil }
                    reducedValues.append(lhs / rhs)
                } else {
                    reducedValues.append(lhs * rhs)
                }
            } else {
                reducedOps.append(op)
                reducedValues.append(rhs)
            }
        }

        // Pass 2: + and −.
        var total = reducedValues[0]
        for (index, op) in reducedOps.enumerated() {
            let rhs = reducedValues[index + 1]
            total = (op == .add) ? total + rhs : total - rhs
        }
        return total
    }

    var resultText: String {
        guard let result else { return "Error" }
        return Formatters.currency(result.roundedToCurrency)
    }

    // MARK: - Input

    mutating func input(digit: String) {
        // Drop a lone leading zero so "0" then "5" reads as "5", not "05".
        if entry == "0" { entry = "" }
        let fractionDigits = entry.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        if fractionDigits.count == 2, fractionDigits[1].count >= maxFractionDigits { return }
        if fractionDigits.count == 1, fractionDigits[0].count >= maxIntegerDigits { return }
        entry.append(digit)
    }

    mutating func inputDecimalPoint() {
        if entry.isEmpty { entry = "0" }
        guard !entry.contains(".") else { return }
        entry.append(".")
    }

    mutating func input(operator op: CalcOperator) {
        if let typed = Self.parse(entry) {
            operands.append(typed)
            operators.append(op)
            entry = ""
            return
        }
        // Nothing typed since the last operator — swap it instead of stacking.
        if !operators.isEmpty {
            operators[operators.count - 1] = op
        } else if !operands.isEmpty {
            operators.append(op)
        } else {
            operands.append(.zero)
            operators.append(op)
        }
    }

    /// Collapses the whole expression down to its result, ready to keep typing on.
    mutating func evaluate() {
        guard let result else { return }
        operands = [result.roundedToCurrency]
        operators = []
        entry = ""
    }

    mutating func backspace() {
        if !entry.isEmpty {
            entry.removeLast()
            if entry == "0" { entry = "" }
            return
        }
        if !operators.isEmpty {
            operators.removeLast()
            // Bring the preceding operand back into the entry field for editing.
            if let last = operands.popLast() {
                entry = Self.plainString(last)
            }
            return
        }
        if let last = operands.popLast() {
            var text = Self.plainString(last)
            text.removeLast()
            entry = text
        }
    }

    mutating func clear() {
        operands = []
        operators = []
        entry = ""
    }

    mutating func setValue(_ value: Decimal) {
        operands = []
        operators = []
        entry = value == 0 ? "" : Self.plainString(value.roundedToCurrency)
    }

    // MARK: - Helpers

    private static func parse(_ text: String) -> Decimal? {
        guard !text.isEmpty, text != "." else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func format(_ value: Decimal) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...6)))
    }

    /// Unformatted, dot-separated text suitable for putting back in the entry field.
    private static func plainString(_ value: Decimal) -> String {
        var text = NSDecimalNumber(decimal: value).description(withLocale: Locale(identifier: "en_US_POSIX"))
        if text.contains("."), text.hasSuffix("0") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }
}
