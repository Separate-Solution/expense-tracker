import SwiftUI

/// Amount entry with inline arithmetic. The display shows the expression being
/// typed and, once an operator is involved, the running total beneath it.
struct CalculatorKeypad: View {

    @Binding var engine: CalculatorEngine
    /// Tint used for the amount — matches the expense/income direction.
    var tint: Color = .primary
    var confirmLabel: String = "Done"
    var confirmEnabled: Bool = true
    var onConfirm: () -> Void

    private enum Key: Hashable {
        case digit(String)
        case doubleZero
        case decimalPoint
        case op(CalcOperator)
        case clear
        case backspace
        case equals
        case confirm
    }

    private let rows: [[Key]] = [
        [.clear, .backspace, .equals, .op(.divide)],
        [.digit("7"), .digit("8"), .digit("9"), .op(.multiply)],
        [.digit("4"), .digit("5"), .digit("6"), .op(.subtract)],
        [.digit("1"), .digit("2"), .digit("3"), .op(.add)],
        [.decimalPoint, .digit("0"), .doubleZero, .confirm]
    ]

    var body: some View {
        VStack(spacing: 14) {
            display
            grid
        }
    }

    // MARK: - Display

    private var display: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(engine.displayText)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.15), value: engine.displayText)

            // Only worth showing once there is arithmetic to resolve.
            Text(engine.hasExpression ? "= \(engine.resultText)" : " ")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Keys

    private var grid: some View {
        VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(rows[rowIndex], id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: Key) -> some View {
        let isConfirm = key == .confirm
        let disabled = isConfirm && !confirmEnabled

        Button {
            handle(key)
        } label: {
            keyLabel(key)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(background(for: key))
                )
                .foregroundStyle(foreground(for: key))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(accessibilityLabel(for: key))
    }

    @ViewBuilder
    private func keyLabel(_ key: Key) -> some View {
        switch key {
        case .digit(let value):
            Text(value).font(.system(size: 24, weight: .medium, design: .rounded))
        case .doubleZero:
            Text("00").font(.system(size: 22, weight: .medium, design: .rounded))
        case .decimalPoint:
            Text(".").font(.system(size: 26, weight: .semibold, design: .rounded))
        case .op(let op):
            Text(op.symbol).font(.system(size: 24, weight: .medium, design: .rounded))
        case .clear:
            Text("C").font(.system(size: 20, weight: .semibold, design: .rounded))
        case .backspace:
            Image(systemName: "delete.left").font(.system(size: 19, weight: .medium))
        case .equals:
            Text("=").font(.system(size: 24, weight: .medium, design: .rounded))
        case .confirm:
            Label(confirmLabel, systemImage: "checkmark")
                .labelStyle(.iconOnly)
                .font(.system(size: 21, weight: .bold))
        }
    }

    private func background(for key: Key) -> Color {
        switch key {
        case .confirm: return .accentColor
        case .op, .equals, .clear, .backspace: return Color(.tertiarySystemFill)
        default: return Color(.secondarySystemFill)
        }
    }

    private func foreground(for key: Key) -> Color {
        switch key {
        case .confirm: return .white
        case .clear: return Theme.expense
        case .op, .equals: return .accentColor
        default: return .primary
        }
    }

    private func accessibilityLabel(for key: Key) -> String {
        switch key {
        case .digit(let value): return value
        case .doubleZero: return "Double zero"
        case .decimalPoint: return "Decimal point"
        case .op(let op): return op.symbol
        case .clear: return "Clear"
        case .backspace: return "Delete"
        case .equals: return "Equals"
        case .confirm: return confirmLabel
        }
    }

    private func handle(_ key: Key) {
        switch key {
        case .digit(let value):
            engine.input(digit: value)
        case .doubleZero:
            engine.input(digit: "0")
            engine.input(digit: "0")
        case .decimalPoint:
            engine.inputDecimalPoint()
        case .op(let op):
            engine.input(operator: op)
        case .clear:
            engine.clear()
        case .backspace:
            engine.backspace()
        case .equals:
            engine.evaluate()
        case .confirm:
            engine.evaluate()
            onConfirm()
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
    }
}
