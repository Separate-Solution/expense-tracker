import SwiftUI

/// Currency label that colours itself by direction and keeps a consistent
/// tabular width so columns of numbers line up.
struct AmountText: View {
    let amount: Decimal
    var type: TransactionType?
    var font: Font = .body
    var weight: Font.Weight = .semibold
    /// When false the value is shown plain, without a +/− prefix or colour.
    var showsSign: Bool = true
    /// Transfers move money without being spending or income, so they keep the
    /// sign but drop the red/green colouring that would read as either.
    var isNeutral: Bool = false

    /// The amount with `type`'s sign applied, or as-is when no type is set.
    private var signedValue: Decimal {
        guard let type else { return amount }
        return abs(amount) * type.sign
    }

    /// Red for money out, green for money in, plain when signs are hidden.
    private var tint: Color {
        guard showsSign, !isNeutral else { return .primary }
        if signedValue < 0 { return Theme.expense }
        if signedValue > 0 { return Theme.income }
        return .secondary
    }

    var body: some View {
        Text(showsSign ? Formatters.signedCurrency(signedValue) : Formatters.currencyMagnitude(amount))
            .font(font.weight(weight))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
