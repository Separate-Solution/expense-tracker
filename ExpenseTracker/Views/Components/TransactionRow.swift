import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction
    var showsDate: Bool = false
    /// Time of day is worth showing where rows are already grouped by day.
    var showsTime: Bool = false

    /// A movement has no category, so it borrows the look of the thing it
    /// moves money to — the card it settles, or the account it lands in.
    private var badgeSymbol: String {
        if transaction.isCardPayment { return "creditcard" }
        if transaction.isTransfer { return "arrow.left.arrow.right" }
        return transaction.category?.symbol ?? CategoryIcon.fallback(for: transaction.type)
    }

    private var badgeColorHex: String {
        if transaction.isCardPayment {
            return transaction.creditCard?.colorHex ?? Theme.paletteHexes[8]
        }
        if transaction.isTransfer {
            return transaction.toAccount?.colorHex ?? Theme.paletteHexes[8]
        }
        return transaction.category?.colorHex ?? Theme.paletteHexes[8]
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(symbolName: badgeSymbol, colorHex: badgeColorHex)

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    // A movement has no category; naming both ends is what
                    // actually tells you what the row is.
                    Text(transaction.isMovement
                         ? transaction.kind.title
                         : (transaction.category?.name ?? "Uncategorized"))
                    if let detail = transaction.movementSummary ?? transaction.sourceName {
                        Text("·")
                        Text(detail)
                    }
                    if showsDate {
                        Text("·")
                        Text(transaction.date.formatted(.dateTime.day().month(.abbreviated)))
                    }
                    if showsTime {
                        Text("·")
                        Text(transaction.date.formatted(Formatters.timeOfDay))
                    }
                    if transaction.isRecurringInstance {
                        Image(systemName: "repeat")
                            .font(.caption2)
                    }
                    if transaction.isMovement {
                        Image(systemName: transaction.kind.symbolName)
                            .font(.caption2)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                AmountText(
                    amount: transaction.amount,
                    type: transaction.type,
                    font: .callout,
                    isNeutral: transaction.isMovement
                )
                if transaction.isScheduled {
                    Text("Upcoming")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
