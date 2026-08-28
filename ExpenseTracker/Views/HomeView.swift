import SwiftUI
import SwiftData

/// A single row in the "Upcoming" list — either a real future-dated transaction
/// or a projection of the next occurrence of a recurring rule.
struct UpcomingItem: Identifiable {
    let id: String
    let title: String
    let emoji: String
    let colorHex: String
    let amount: Decimal
    let type: TransactionType
    let date: Date
    let isProjection: Bool
}

struct HomeView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortIndex)
    private var accounts: [Account]
    @Query private var rules: [RecurringRule]

    @State private var monthAnchor = Date().startOfMonth
    @State private var editingTransaction: Transaction?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    monthSwitcher
                    summaryCard
                    if !accounts.isEmpty { accountsStrip }
                    if !upcoming.isEmpty { upcomingSection }
                    topCategoriesSection
                    recentSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                // Room for the floating button so it never covers the last row.
                .padding(.bottom, 96)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Overview")
            .sheet(item: $editingTransaction) { transaction in
                TransactionEditorView(transaction: transaction)
            }
        }
    }

    // MARK: - Month scope

    private var monthRange: ClosedRange<Date> {
        monthAnchor.startOfMonth...monthAnchor.endOfMonth
    }

    private var monthTransactions: [Transaction] {
        transactions.filter { monthRange.contains($0.date) }
    }

    private var monthIncome: Decimal {
        monthTransactions.filter { $0.type == .income }.reduce(.zero) { $0 + $1.amount }
    }

    private var monthExpense: Decimal {
        monthTransactions.filter { $0.type == .expense }.reduce(.zero) { $0 + $1.amount }
    }

    private var monthSwitcher: some View {
        HStack {
            Button {
                monthAnchor = monthAnchor.addingMonths(-1)
            } label: {
                Image(systemName: "chevron.left").font(.headline)
            }

            Spacer()

            VStack(spacing: 1) {
                Text(monthAnchor.formatted(Formatters.monthTitle))
                    .font(.headline)
                if !Calendar.current.isDate(monthAnchor, equalTo: Date(), toGranularity: .month) {
                    Button("Back to this month") { monthAnchor = Date().startOfMonth }
                        .font(.caption2)
                }
            }

            Spacer()

            Button {
                monthAnchor = monthAnchor.addingMonths(1)
            } label: {
                Image(systemName: "chevron.right").font(.headline)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Net this month")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AmountText(
                    amount: monthIncome - monthExpense,
                    font: .system(size: 34, design: .rounded),
                    weight: .bold
                )
            }

            Divider()

            HStack(spacing: 0) {
                summaryColumn(title: "Income", amount: monthIncome, tint: Theme.income)
                Divider().frame(height: 34)
                summaryColumn(title: "Spent", amount: monthExpense, tint: Theme.expense)
            }
        }
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private func summaryColumn(title: String, amount: Decimal, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Formatters.currencyMagnitude(amount))
                .font(.headline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Accounts

    private var accountsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Accounts")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(accounts) { account in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                AccountBadge(symbolName: account.symbolName, colorHex: account.colorHex, size: 28)
                                Text(account.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                            Text(Formatters.signedCurrency(account.currentBalance))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(account.kind.shortTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 150, alignment: .leading)
                        .cardBackground()
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    // MARK: - Upcoming

    /// Future-dated transactions plus the next unposted occurrence of each active
    /// rule, so subscriptions show up before they are actually charged.
    private var upcoming: [UpcomingItem] {
        let horizon = Date().addingMonths(2)
        var items: [UpcomingItem] = transactions
            .filter { $0.isScheduled && $0.date <= horizon }
            .map { transaction in
                UpcomingItem(
                    id: transaction.id.uuidString,
                    title: transaction.title,
                    emoji: transaction.category?.emoji ?? "🏷️",
                    colorHex: transaction.category?.colorHex ?? Theme.paletteHexes[8],
                    amount: transaction.amount,
                    type: transaction.type,
                    date: transaction.date,
                    isProjection: false
                )
            }

        for rule in rules where rule.isActive {
            guard let next = rule.nextOccurrence(), next <= horizon else { continue }
            items.append(
                UpcomingItem(
                    id: "rule-\(rule.id.uuidString)",
                    title: rule.title,
                    emoji: rule.category?.emoji ?? "🔁",
                    colorHex: rule.category?.colorHex ?? Theme.paletteHexes[5],
                    amount: rule.amount,
                    type: rule.type,
                    date: next,
                    isProjection: true
                )
            )
        }

        return items.sorted { $0.date < $1.date }.prefix(5).map { $0 }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Upcoming")
            VStack(spacing: 0) {
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        CategoryBadge(emoji: item.emoji, colorHex: item.colorHex, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline).lineLimit(1)
                            HStack(spacing: 4) {
                                Text(Formatters.relativeDayLabel(for: item.date))
                                if item.isProjection {
                                    Image(systemName: "repeat").font(.caption2)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        AmountText(amount: item.amount, type: item.type, font: .subheadline)
                    }
                    .padding(.vertical, 8)

                    if index < upcoming.count - 1 { Divider() }
                }
            }
            .cardBackground()
        }
    }

    // MARK: - Top categories

    private struct CategoryTotal: Identifiable {
        let id: String
        let name: String
        let emoji: String
        let colorHex: String
        let total: Decimal
        let share: Double
    }

    private var topCategories: [CategoryTotal] {
        let expenses = monthTransactions.filter { $0.type == .expense }
        guard !expenses.isEmpty else { return [] }
        let total = expenses.reduce(Decimal.zero) { $0 + $1.amount }
        guard total > 0 else { return [] }

        var buckets: [String: (name: String, emoji: String, colorHex: String, sum: Decimal)] = [:]
        for transaction in expenses {
            let key = transaction.category?.id.uuidString ?? "uncategorized"
            let name = transaction.category?.name ?? "Uncategorized"
            let emoji = transaction.category?.emoji ?? "🏷️"
            let colorHex = transaction.category?.colorHex ?? Theme.paletteHexes[8]
            let existing = buckets[key]?.sum ?? .zero
            buckets[key] = (name, emoji, colorHex, existing + transaction.amount)
        }

        return buckets
            .map { key, value in
                CategoryTotal(
                    id: key,
                    name: value.name,
                    emoji: value.emoji,
                    colorHex: value.colorHex,
                    total: value.sum,
                    share: (value.sum / total).doubleValue
                )
            }
            .sorted { $0.total > $1.total }
            .prefix(5)
            .map { $0 }
    }

    @ViewBuilder
    private var topCategoriesSection: some View {
        if !topCategories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader("Where it went")
                VStack(spacing: 12) {
                    ForEach(topCategories) { entry in
                        VStack(spacing: 5) {
                            HStack(spacing: 10) {
                                Text(entry.emoji).font(.callout)
                                Text(entry.name).font(.subheadline).lineLimit(1)
                                Spacer()
                                Text(Formatters.currencyMagnitude(entry.total))
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                                Text("\(Int((entry.share * 100).rounded()))%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 38, alignment: .trailing)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color(.tertiarySystemFill))
                                    Capsule()
                                        .fill(Color(hex: entry.colorHex))
                                        .frame(width: max(4, proxy.size.width * entry.share))
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
                .cardBackground()
            }
        }
    }

    // MARK: - Recent

    private var recentPosted: [Transaction] {
        monthTransactions.filter { !$0.isScheduled }.prefix(8).map { $0 }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Recent")
            if recentPosted.isEmpty {
                EmptyStateView(
                    symbol: "tray",
                    title: "Nothing logged yet",
                    message: "Tap the + button to add your first transaction for this month."
                )
                .cardBackground()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentPosted.enumerated()), id: \.element.id) { index, transaction in
                        Button {
                            editingTransaction = transaction
                        } label: {
                            TransactionRow(transaction: transaction, showsDate: true)
                        }
                        .buttonStyle(.plain)

                        if index < recentPosted.count - 1 { Divider() }
                    }
                }
                .cardBackground()
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}
