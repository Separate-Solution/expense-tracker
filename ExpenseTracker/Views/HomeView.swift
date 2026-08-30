import SwiftUI
import SwiftData

/// A single row in the "Upcoming" list — either a real future-dated transaction
/// or a projection of the next occurrence of a recurring rule.
struct UpcomingItem: Identifiable {
    let id: String
    let title: String
    let symbolName: String
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
    @Query(filter: #Predicate<CreditCard> { !$0.isArchived }, sort: \CreditCard.sortIndex)
    private var cards: [CreditCard]
    @Query private var rules: [RecurringRule]
    @Query(sort: \Budget.sortIndex) private var budgets: [Budget]

    @State private var monthAnchor = Date().startOfMonth
    @State private var editingTransaction: Transaction?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    monthSwitcher
                    summaryCard
                    if !cards.isEmpty {
                        CreditCardDueSection(cards: cards, accounts: accounts)
                    }
                    // TODO: Every active budget is shown here for now. Once the
                    // dashboard can be arranged by hand, this becomes whichever
                    // budgets have been pinned to it, alongside whatever else
                    // the user pins.
                    if !activeBudgets.isEmpty {
                        BudgetsDashboardSection(budgets: activeBudgets, transactions: transactions)
                    }
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

    /// Budgets on the dashboard. Archiving one is how it is put away, so an
    /// archived budget stays off here as well as out of the list's Active
    /// section.
    private var activeBudgets: [Budget] { budgets.filter { !$0.isArchived } }

    // MARK: - Month scope

    private var monthRange: ClosedRange<Date> {
        monthAnchor.startOfMonth...monthAnchor.endOfMonth
    }

    private var monthTransactions: [Transaction] {
        transactions.filter { monthRange.contains($0.date) }
    }

    /// The month's rows that count as real money in or out. Card bill payments
    /// are left out: they settle purchases that were already counted as spending
    /// when they were made, so including them would double up.
    private var monthSpendable: [Transaction] {
        monthTransactions.filter(\.countsTowardsTotals)
    }

    private var monthIncome: Decimal {
        monthSpendable.filter { $0.type == .income }.reduce(.zero) { $0 + $1.amount }
    }

    private var monthExpense: Decimal {
        monthSpendable.filter { $0.type == .expense }.reduce(.zero) { $0 + $1.amount }
    }

    /// What you are actually worth right now: everything in your accounts and
    /// cash, less everything owed on cards. Unlike the figures beside it this
    /// is not scoped to the month being browsed — it is today’s position.
    private var netWorth: Decimal {
        let assets = accounts.reduce(Decimal.zero) { $0 + $1.currentBalance }
        let debts = cards.reduce(Decimal.zero) { $0 + $1.outstanding }
        return assets - debts
    }

    /// Names the scope of the month figures, since the net worth above them
    /// does not move with the month switcher.
    private var monthScopeLabel: String {
        Calendar.current.isDate(monthAnchor, equalTo: Date(), toGranularity: .month)
            ? "This month"
            : monthAnchor.formatted(Formatters.monthTitle)
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
                Text("Net worth")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Formatters.balance(netWorth))
                    .font(.system(size: 34, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(netWorth < 0 ? Theme.expense : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(netWorthCaption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(spacing: 8) {
                Text(monthScopeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    summaryColumn(title: "Income", amount: monthIncome, tint: Theme.income)
                    Divider().frame(height: 34)
                    summaryColumn(title: "Spent", amount: monthExpense, tint: Theme.expense)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private var netWorthCaption: String {
        cards.isEmpty
            ? "Across your accounts and cash"
            : "Accounts and cash, less what you owe on cards"
    }

    /// One labelled figure in the month summary card.
    /// - Parameters:
    ///   - title: Caption above the figure, e.g. "Income".
    ///   - amount: The value to show.
    ///   - tint: Colour for the amount.
    /// - Returns: The configured column view.
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
            sectionHeader("Bank Accounts")
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
                    symbolName: transaction.category?.symbol
                        ?? CategoryIcon.fallback(for: transaction.type),
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
                    symbolName: rule.category?.symbol ?? CategoryIcon.recurringFallback,
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
                        CategoryBadge(symbolName: item.symbolName, colorHex: item.colorHex, size: 34)
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
        let symbolName: String
        let colorHex: String
        let total: Decimal
        let share: Double
    }

    private var topCategories: [CategoryTotal] {
        let expenses = monthSpendable.filter { $0.type == .expense }
        guard !expenses.isEmpty else { return [] }
        let total = expenses.reduce(Decimal.zero) { $0 + $1.amount }
        guard total > 0 else { return [] }

        var buckets: [String: (name: String, symbolName: String, colorHex: String, sum: Decimal)] = [:]
        for transaction in expenses {
            let key = transaction.category?.id.uuidString ?? "uncategorized"
            let name = transaction.category?.name ?? "Uncategorized"
            let symbolName = transaction.category?.symbol ?? CategoryIcon.expenseFallback
            let colorHex = transaction.category?.colorHex ?? Theme.paletteHexes[8]
            let existing = buckets[key]?.sum ?? .zero
            buckets[key] = (name, symbolName, colorHex, existing + transaction.amount)
        }

        return buckets
            .map { key, value in
                CategoryTotal(
                    id: key,
                    name: value.name,
                    symbolName: value.symbolName,
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
                                Image(systemName: entry.symbolName)
                                    .font(.callout)
                                    .foregroundStyle(Color(hex: entry.colorHex))
                                    .frame(width: 22)
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

    /// A section title styled consistently across the overview.
    /// - Parameter title: The heading text.
    /// - Returns: The styled header view.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }
}
