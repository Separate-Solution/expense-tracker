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

    private var signedValue: Decimal {
        guard let type else { return amount }
        return abs(amount) * type.sign
    }

    private var tint: Color {
        guard showsSign else { return .primary }
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
