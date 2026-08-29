import SwiftUI
import SwiftData

struct TransactionsView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var searchText = ""
    @State private var typeFilter: TransactionType?
    @State private var accountFilter: UUID?
    @State private var categoryFilter: UUID?
    @State private var editingTransaction: Transaction?
    @State private var pendingDeletion: Transaction?

    private var hasActiveFilter: Bool {
        typeFilter != nil || accountFilter != nil || categoryFilter != nil
    }

    private var filtered: [Transaction] {
        transactions.filter { transaction in
            if let typeFilter, transaction.type != typeFilter { return false }
            if let accountFilter, transaction.account?.id != accountFilter { return false }
            if let categoryFilter, transaction.category?.id != categoryFilter { return false }
            guard !searchText.isEmpty else { return true }
            let needle = searchText.lowercased()
            return transaction.title.lowercased().contains(needle)
                || transaction.note.lowercased().contains(needle)
                || (transaction.category?.name.lowercased().contains(needle) ?? false)
                || (transaction.account?.name.lowercased().contains(needle) ?? false)
        }
    }

    /// Grouped into day sections, newest first, with a per-day net total.
    private var sections: [(date: Date, items: [Transaction])] {
        let grouped = Dictionary(grouping: filtered) { $0.date.startOfDay }
        return grouped
            .map { (date: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.date > $1.date }
    }

    private var filteredTotal: Decimal {
        filtered.reduce(Decimal.zero) { $0 + $1.signedAmount }
    }

    var body: some View {
        NavigationStack {
            // One List for both states, rather than swapping in a ScrollView when
            // empty: the navigation bar binds its large-title behaviour to a single
            // scroll view, and a branch that replaces it leaves the title collapsed.
            // The List also has to be the stack's direct child — wrapping it in a
            // VStack to pin the search box stops the title collapsing on scroll.
            List {
                Section {
                    SearchField(text: $searchText, prompt: "Search transactions")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
                }

                if filtered.isEmpty {
                    Section {
                        EmptyStateView(
                            symbol: transactions.isEmpty ? "tray" : "line.3.horizontal.decrease.circle",
                            title: transactions.isEmpty ? "No transactions yet" : "Nothing matches",
                            message: transactions.isEmpty
                                ? "Tap the + button to log your first one."
                                : "Try clearing the search or filters."
                        )
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } else {
                    Section {
                        HStack {
                            Text("\(filtered.count) transaction\(filtered.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            AmountText(amount: filteredTotal, font: .caption)
                        }
                        .listRowBackground(Color.clear)
                    }

                    ForEach(sections, id: \.date) { section in
                        Section {
                            ForEach(section.items) { transaction in
                                Button {
                                    editingTransaction = transaction
                                } label: {
                                    TransactionRow(transaction: transaction)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        pendingDeletion = transaction
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text(Formatters.relativeDayLabel(for: section.date))
                                Spacer()
                                Text(Formatters.signedCurrency(
                                    section.items.reduce(Decimal.zero) { $0 + $1.signedAmount }
                                ))
                                .monospacedDigit()
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }

                    // Keeps the last row clear of the floating button.
                    Color.clear
                        .frame(height: 70)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            // The custom search box doesn't get `.searchable`'s built-in
            // dismiss-on-scroll. `.immediately` rather than `.interactively`:
            // the latter only tracks a downward drag toward the keyboard, so
            // scrolling up through results would leave it covering them.
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Transactions")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    filterMenu
                }
            }
            .sheet(item: $editingTransaction) { transaction in
                TransactionEditorView(transaction: transaction)
            }
            .confirmationDialog(
                "Delete this transaction?",
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let pendingDeletion {
                        context.delete(pendingDeletion)
                        try? context.save()
                    }
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Type", selection: $typeFilter) {
                Text("All types").tag(TransactionType?.none)
                ForEach(TransactionType.allCases) { option in
                    Text(option.title).tag(Optional(option))
                }
            }

            Picker("Account", selection: $accountFilter) {
                Text("All accounts").tag(UUID?.none)
                ForEach(accounts) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }

            Picker("Category", selection: $categoryFilter) {
                Text("All categories").tag(UUID?.none)
                ForEach(categories) { category in
                    Label(category.name, systemImage: category.symbol).tag(Optional(category.id))
                }
            }

            if hasActiveFilter {
                Divider()
                Button("Clear filters", systemImage: "xmark.circle") {
                    typeFilter = nil
                    accountFilter = nil
                    categoryFilter = nil
                }
            }
        } label: {
            Image(systemName: hasActiveFilter
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }
}
