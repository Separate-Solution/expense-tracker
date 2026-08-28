import SwiftUI

struct TransactionRow: View {
    let transaction: Transaction
    var showsDate: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(
                emoji: transaction.category?.emoji ?? "🏷️",
                colorHex: transaction.category?.colorHex ?? Theme.paletteHexes[8]
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(transaction.category?.name ?? "Uncategorized")
                    if let account = transaction.account {
                        Text("·")
                        Text(account.name)
                    }
                    if showsDate {
                        Text("·")
                        Text(transaction.date.formatted(.dateTime.day().month(.abbreviated)))
                    }
                    if transaction.isRecurringInstance {
                        Image(systemName: "repeat")
                            .font(.caption2)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                AmountText(amount: transaction.amount, type: transaction.type, font: .callout)
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
