import SwiftUI
import SwiftData

struct TransactionsView: View {

    @Environment(\.modelContext) private var context

    /// Owned by `RootView` so the floating add button can step aside while
    /// rows are being selected.
    @Binding var isSelecting: Bool

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \CreditCard.sortIndex) private var cards: [CreditCard]
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var searchText = ""
    @State private var typeFilter: TransactionType?
    @State private var sourceFilter: PaymentSource?
    @State private var categoryFilter: UUID?
    @State private var editingTransaction: Transaction?
    @State private var pendingDeletion: Transaction?
    @State private var selectedIDs: Set<UUID> = []
    @State private var isConfirmingBulkDeletion = false
    @State private var saveFailure: String?

    private var hasActiveFilter: Bool {
        typeFilter != nil || sourceFilter != nil || categoryFilter != nil
    }

    private var filtered: [Transaction] {
        transactions.filter { transaction in
            if let typeFilter, transaction.type != typeFilter { return false }
            if let sourceFilter, transaction.paymentSource != sourceFilter { return false }
            if let categoryFilter, transaction.category?.id != categoryFilter { return false }
            guard !searchText.isEmpty else { return true }
            let needle = searchText.lowercased()
            return transaction.title.lowercased().contains(needle)
                || transaction.note.lowercased().contains(needle)
                || (transaction.category?.name.lowercased().contains(needle) ?? false)
                || (transaction.account?.name.lowercased().contains(needle) ?? false)
                || (transaction.creditCard?.name.lowercased().contains(needle) ?? false)
        }
    }

    /// Grouped into day sections, newest first, with a per-day net total.
    private var sections: [(date: Date, items: [Transaction])] {
        let grouped = Dictionary(grouping: filtered) { $0.date.startOfDay }
        return grouped
            .map { group in
                // Later in the day first; `createdAt` only breaks ties between
                // two transactions logged at the same time.
                let items = group.value.sorted {
                    $0.date == $1.date ? $0.createdAt > $1.createdAt : $0.date > $1.date
                }
                return (date: group.key, items: items)
            }
            .sorted { $0.date > $1.date }
    }

    /// Card bill payments are shown in the list but left out of every total:
    /// they settle purchases that are already listed as spending, so counting
    /// them again would double up.
    private var filteredTotal: Decimal {
        Self.total(of: filtered)
    }

    /// How many rows on screen are excluded from the totals, so the figure can
    /// say why it doesn't match the rows above it.
    private var excludedPaymentCount: Int {
        filtered.filter { !$0.countsTowardsTotals }.count
    }

    /// Nets a set of rows, ignoring anything that doesn't count as money in or out.
    /// - Parameter transactions: The rows to total.
    /// - Returns: The net of the countable ones.
    private static func total(of transactions: [Transaction]) -> Decimal {
        transactions
            .filter(\.countsTowardsTotals)
            .reduce(Decimal.zero) { $0 + $1.signedAmount }
    }

    /// The transactions the bulk actions apply to — always the selected rows
    /// that the current search and filters still show.
    private var selectedTransactions: [Transaction] {
        filtered.filter { selectedIDs.contains($0.id) }
    }

    private var isEverythingSelected: Bool {
        !filtered.isEmpty && selectedTransactions.count == filtered.count
    }

    /// Only ever counts rows the actions can actually reach: a `@Query` update
    /// can retire a selected transaction without the filters having changed.
    private var selectionCount: Int { selectedTransactions.count }

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
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text("\(filtered.count) transaction\(filtered.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                AmountText(amount: filteredTotal, font: .caption)
                            }
                            if excludedPaymentCount > 0 {
                                Text("Totals leave out \(excludedPaymentCount) card payment\(excludedPaymentCount == 1 ? "" : "s") \u{2014} the spending they settle is already listed.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .listRowBackground(Color.clear)
                    }

                    ForEach(sections, id: \.date) { section in
                        Section {
                            ForEach(section.items) { transaction in
                                row(for: transaction)
                            }
                        } header: {
                            HStack {
                                Text(Formatters.relativeDayLabel(for: section.date))
                                Spacer()
                                Text(Formatters.signedCurrency(Self.total(of: section.items)))
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
                ToolbarItem(placement: .topBarLeading) {
                    if isSelecting {
                        Button("Done") { endSelection() }
                    } else if !filtered.isEmpty {
                        Button("Select") {
                            withAnimation(.snappy(duration: 0.2)) { isSelecting = true }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button(isEverythingSelected ? "Deselect All" : "Select All") {
                            // Scoped to what the filters currently show, so
                            // "Select All" never reaches a hidden transaction.
                            selectedIDs = isEverythingSelected ? [] : Set(filtered.map(\.id))
                        }
                    } else {
                        filterMenu
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    selectionActionBar
                        .transition(.move(edge: .bottom))
                }
            }
            // Filters can change under a selection; drop anything they hide so
            // the actions only ever touch rows that are on screen.
            .onChange(of: filterSignature) { _, _ in
                selectedIDs = Set(selectedTransactions.map(\.id))
            }
            .onChange(of: isSelecting) { _, selecting in
                if !selecting { selectedIDs = [] }
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
                        saveFailure = context.saveReportingFailure()
                    }
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            }
            .confirmationDialog(
                selectionCount == 1
                    ? "Delete this transaction?"
                    : "Delete \(selectionCount) transactions?",
                isPresented: $isConfirmingBulkDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: deleteSelected)
                Button("Cancel", role: .cancel) { }
            }
            .saveFailureAlert($saveFailure)
        }
    }

    // MARK: - Rows

    /// One transaction row — a checkbox toggle while selecting, otherwise a
    /// button that opens the editor.
    /// - Parameter transaction: The transaction to render.
    /// - Returns: The configured row.
    private func row(for transaction: Transaction) -> some View {
        let isSelected = selectedIDs.contains(transaction.id)
        return Button {
            if isSelecting {
                toggleSelection(of: transaction)
            } else {
                editingTransaction = transaction
            }
        } label: {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .accessibilityHidden(true)
                }
                TransactionRow(transaction: transaction, showsTime: true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelecting && isSelected ? [.isSelected] : [])
        .swipeActions(edge: .trailing) {
            if !isSelecting {
                Button(role: .destructive) {
                    pendingDeletion = transaction
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .swipeActions(edge: .leading) {
            if !isSelecting {
                Button {
                    duplicate([transaction])
                } label: {
                    Label("Duplicate", systemImage: "plus.square.on.square")
                }
                .tint(.accentColor)
            }
        }
    }

    private var selectionActionBar: some View {
        HStack {
            Button(role: .destructive) {
                isConfirmingBulkDeletion = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)

            Spacer()

            Text(selectionCount == 0 ? "Select transactions" : "\(selectionCount) selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                duplicate(selectedTransactions)
                endSelection()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
        }
        .disabled(selectionCount == 0)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Filters

    /// Everything the filtered list depends on, so a change can prune the
    /// selection without recomputing the whole list to compare it.
    private var filterSignature: String {
        [typeFilter?.rawValue ?? "", sourceFilter?.id ?? "",
         categoryFilter?.uuidString ?? "", searchText].joined(separator: "|")
    }

    private var filterMenu: some View {
        Menu {
            Picker("Type", selection: $typeFilter) {
                Text("All types").tag(TransactionType?.none)
                ForEach(TransactionType.allCases) { option in
                    Text(option.title).tag(Optional(option))
                }
            }

            PaymentSourcePicker(
                label: "Paid with",
                accounts: accounts,
                cards: cards,
                noneLabel: "All sources",
                selection: $sourceFilter
            )

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
                    sourceFilter = nil
                    categoryFilter = nil
                }
            }
        } label: {
            Image(systemName: hasActiveFilter
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: - Selection actions

    /// Adds or removes one transaction from the selection.
    /// - Parameter transaction: The row that was tapped.
    private func toggleSelection(of transaction: Transaction) {
        if selectedIDs.contains(transaction.id) {
            selectedIDs.remove(transaction.id)
        } else {
            selectedIDs.insert(transaction.id)
        }
    }

    private func endSelection() {
        withAnimation(.snappy(duration: 0.2)) {
            isSelecting = false
            selectedIDs = []
        }
    }

    /// Deletes the selected transactions and leaves selection mode.
    private func deleteSelected() {
        let doomed = selectedTransactions
        guard !doomed.isEmpty else { return }
        for transaction in doomed {
            context.delete(transaction)
        }
        if let failure = context.saveReportingFailure() {
            saveFailure = failure
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        endSelection()
    }

    /// Inserts a standalone copy of each transaction, keeping its date, time
    /// and every other field.
    /// - Parameter originals: The transactions to copy.
    private func duplicate(_ originals: [Transaction]) {
        guard !originals.isEmpty else { return }
        var copies: [Transaction] = []
        for original in originals {
            let copy = original.duplicated()
            context.insert(copy)
            copies.append(copy)
        }
        if let failure = context.saveReportingFailure() {
            copies.forEach { context.delete($0) }
            saveFailure = failure
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
