import SwiftUI
import SwiftData

/// Create or edit a budget: what kind it is, how much it allows over what
/// stretch of time, and which transactions it counts.
struct BudgetEditorView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil means "create a new budget".
    let budget: Budget?

    @Query(sort: \Budget.sortIndex) private var budgets: [Budget]
    @Query(sort: \Category.sortIndex) private var allCategories: [Category]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortIndex)
    private var accounts: [Account]
    @Query(filter: #Predicate<CreditCard> { !$0.isArchived }, sort: \CreditCard.sortIndex)
    private var cards: [CreditCard]

    @State private var kind: BudgetKind = .expense
    @State private var name = ""
    @State private var amount: Decimal = .zero
    @State private var period: BudgetPeriod = .month
    @State private var periodInterval = 1
    @State private var startDate = Date()
    @State private var endDate = Date().addingMonths(1)
    @State private var scope: BudgetScope = .allExpenses
    @State private var includedCategoryIDs: Set<UUID> = []
    @State private var excludedCategoryIDs: Set<UUID> = []
    @State private var accountIDs: Set<UUID> = []
    @State private var cardIDs: Set<UUID> = []
    @State private var colorHex = Theme.paletteHexes[0]
    @State private var note = ""
    @State private var isShowingAmountPad = false
    @State private var saveFailure: Error?

    private var isNew: Bool { budget == nil }

    private var canSave: Bool {
        amount > 0
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(scope.needsCategorySelection && includedCategoryIDs.isEmpty)
    }

    /// The window the budget as configured would be in, so the footer can show
    /// real dates rather than a description of them.
    private var previewPeriod: DateInterval {
        let schedule = BudgetSchedule(
            period: period,
            interval: max(1, periodInterval),
            startDate: startDate,
            endDate: period.isRepeating ? nil : endDate
        )
        // A budget starting in the future has no current period yet; showing the
        // first one is more use than showing none.
        return schedule.period(containing: max(.now, startDate.startOfDay))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(BudgetKind.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { oldValue, newValue in
                        // The scope only follows the type while it is still the
                        // one that type picked for you.
                        if scope == oldValue.defaultScope { scope = newValue.defaultScope }
                    }

                    TextField("Name", text: $name)
                } footer: {
                    Text(kind == .expense
                         ? "An expense budget caps what may go out over each period."
                         : "A savings budget counts what you put aside towards a target.")
                }

                Section {
                    amountAndPeriodRow
                } header: {
                    Text(kind.amountLabel)
                } footer: {
                    Text(amountFooter)
                }

                Section {
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    if !period.isRepeating {
                        DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                } header: {
                    Text("Period")
                } footer: {
                    Text(period.isRepeating
                         ? "Periods are measured from the start date, so one starting on the 31st lands on the 28th in February and back on the 31st in March."
                         : "A custom period runs once between these two dates and doesn't repeat.")
                }

                Section {
                    Picker("Counts", selection: $scope) {
                        ForEach(BudgetScope.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    if scope.needsCategorySelection {
                        NavigationLink {
                            BudgetCategorySelectionView(
                                title: "Categories counted",
                                footer: "Only transactions in these categories count towards the budget.",
                                selection: $includedCategoryIDs
                            )
                        } label: {
                            LabeledContent("Categories", value: countLabel(includedCategoryIDs, empty: "None"))
                        }
                    }
                } header: {
                    Text("Transactions to include")
                } footer: {
                    Text(scope.needsCategorySelection && includedCategoryIDs.isEmpty
                         ? "Pick at least one category, or nothing will count towards this budget."
                         : scope.explanation)
                }

                if !scope.needsCategorySelection {
                    Section {
                        NavigationLink {
                            BudgetCategorySelectionView(
                                title: "Categories excluded",
                                footer: "Transactions in these categories are left out, whatever else the budget counts.",
                                selection: $excludedCategoryIDs
                            )
                        } label: {
                            LabeledContent("Excluded", value: countLabel(excludedCategoryIDs, empty: "None"))
                        }
                    } header: {
                        Text("Categories to exclude")
                    }
                }

                Section {
                    NavigationLink {
                        BudgetSourceSelectionView(
                            accountIDs: $accountIDs,
                            cardIDs: $cardIDs
                        )
                    } label: {
                        LabeledContent("Accounts & cards", value: sourcesLabel)
                    }
                } header: {
                    Text("Accounts")
                } footer: {
                    Text("Leave this empty to count spending from every account and card.")
                }

                Section("Colour") {
                    ColorSwatchPicker(selectedHex: $colorHex)
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(isNew ? "New Budget" : "Edit Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .saveFailureAlert($saveFailure)
            .sheet(isPresented: $isShowingAmountPad) {
                AmountEntrySheet(amount: $amount, type: kind == .expense ? .expense : .income)
            }
        }
        .onAppear(perform: load)
    }

    // MARK: - Rows

    /// The money field with the stretch of time it applies to sitting beside it
    /// — "₹500 / 2 weeks" read left to right as one sentence.
    private var amountAndPeriodRow: some View {
        HStack(spacing: 8) {
            Button {
                isShowingAmountPad = true
            } label: {
                Text(amount > 0 ? Formatters.currencyMagnitude(amount) : "Amount")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(amount > 0 ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .buttonStyle(.plain)

            Text("/").foregroundStyle(.secondary)

            if period.isRepeating {
                TextField("1", value: $periodInterval, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                    )
            }

            Picker("Period", selection: $period) {
                ForEach(BudgetPeriod.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Spacer(minLength: 0)
        }
    }

    private var amountFooter: String {
        let window = "\(previewPeriod.start.formatted(Formatters.shortDate)) "
            + "\u{2013} \(previewPeriod.end.formatted(Formatters.shortDate))"
        guard amount > 0 else { return "This period runs \(window)." }
        let cadence = period.isRepeating
            ? "every \(max(1, periodInterval) == 1 ? "" : "\(periodInterval) ")\(period.unitLabel(interval: max(1, periodInterval)))"
            : "once"
        return "\(Formatters.currencyMagnitude(amount)) \(cadence) \u{2014} this period runs \(window)."
    }

    /// "3 selected", or the empty word when nothing is picked.
    private func countLabel(_ ids: Set<UUID>, empty: String) -> String {
        ids.isEmpty ? empty : "\(ids.count) selected"
    }

    private var sourcesLabel: String {
        let total = accountIDs.count + cardIDs.count
        return total == 0 ? "All" : "\(total) selected"
    }

    // MARK: - Loading and saving

    /// Fills the form from the budget being edited, or picks sensible defaults
    /// for a new one.
    private func load() {
        guard let budget else {
            colorHex = Theme.paletteHexes[budgets.count % Theme.paletteHexes.count]
            return
        }
        kind = budget.kind
        name = budget.name
        amount = budget.amount
        period = budget.period
        periodInterval = budget.periodInterval
        startDate = budget.startDate
        endDate = budget.endDate ?? budget.startDate.addingMonths(1)
        scope = budget.scope
        includedCategoryIDs = Set((budget.includedCategories ?? []).map(\.id))
        excludedCategoryIDs = Set((budget.excludedCategories ?? []).map(\.id))
        accountIDs = Set((budget.accounts ?? []).map(\.id))
        cardIDs = Set((budget.creditCards ?? []).map(\.id))
        colorHex = budget.colorHex
        note = budget.note
    }

    /// Creates or updates the budget and dismisses.
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A scope that doesn't use hand-picked categories keeps none, so
        // switching back and forth can't leave a stale list counting rows the
        // screen no longer shows.
        let included = scope.needsCategorySelection
            ? allCategories.filter { includedCategoryIDs.contains($0.id) }
            : []
        let excluded = scope.needsCategorySelection
            ? []
            : allCategories.filter { excludedCategoryIDs.contains($0.id) }
        // Resolved against every account, not just the unarchived ones, so
        // archiving an account doesn't quietly widen the budget to all of them.
        let selectedAccounts = (try? context.fetch(FetchDescriptor<Account>()))?
            .filter { accountIDs.contains($0.id) } ?? []
        let selectedCards = (try? context.fetch(FetchDescriptor<CreditCard>()))?
            .filter { cardIDs.contains($0.id) } ?? []

        let target: Budget
        if let budget {
            target = budget
        } else {
            target = Budget(
                name: trimmed,
                amount: amount.roundedToCurrency,
                sortIndex: (budgets.map(\.sortIndex).max() ?? -1) + 1
            )
            context.insert(target)
        }

        target.name = trimmed
        target.kind = kind
        target.amount = amount.roundedToCurrency
        target.period = period
        target.periodInterval = max(1, periodInterval)
        target.startDate = startDate.startOfDay
        target.endDate = period.isRepeating ? nil : endDate.endOfDay
        target.scope = scope
        target.includedCategories = included
        target.excludedCategories = excluded
        target.accounts = selectedAccounts
        target.creditCards = selectedCards
        target.colorHex = colorHex
        target.note = note

        if let failure = context.saveReportingFailure() {
            saveFailure = failure
            return
        }
        dismiss()
    }
}

/// Tick list of categories, used for both the counted and the excluded lists.
struct BudgetCategorySelectionView: View {

    let title: String
    let footer: String
    @Binding var selection: Set<UUID>

    @Query(sort: \Category.sortIndex) private var categories: [Category]

    /// Categories of one type, hiding archived ones unless they are already
    /// picked — a budget pointing at one should keep showing it.
    private func categories(ofType type: TransactionType) -> [Category] {
        categories.filter {
            $0.type == type && (!$0.isArchived || selection.contains($0.id))
        }
    }

    var body: some View {
        List {
            ForEach(TransactionType.allCases) { type in
                let items = categories(ofType: type)
                if !items.isEmpty {
                    Section(type.title) {
                        ForEach(items) { category in
                            row(for: category)
                        }
                    }
                }
            }

            Section {
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !selection.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { selection.removeAll() }
                }
            }
        }
    }

    /// One tickable category row.
    /// - Parameter category: The category to render.
    /// - Returns: The configured row.
    private func row(for category: Category) -> some View {
        let isSelected = selection.contains(category.id)
        return Button {
            if isSelected { selection.remove(category.id) } else { selection.insert(category.id) }
        } label: {
            HStack(spacing: 12) {
                CategoryBadge(symbolName: category.symbol, colorHex: category.colorHex)
                Text(category.name).foregroundStyle(.primary)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Tick list of the accounts and cards a budget watches. Nothing ticked means
/// every one of them.
struct BudgetSourceSelectionView: View {

    @Binding var accountIDs: Set<UUID>
    @Binding var cardIDs: Set<UUID>

    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \CreditCard.sortIndex) private var cards: [CreditCard]

    private var visibleAccounts: [Account] {
        accounts.filter { !$0.isArchived || accountIDs.contains($0.id) }
    }

    private var visibleCards: [CreditCard] {
        cards.filter { !$0.isArchived || cardIDs.contains($0.id) }
    }

    var body: some View {
        List {
            if !visibleAccounts.isEmpty {
                Section("Bank Accounts") {
                    ForEach(visibleAccounts) { account in
                        row(
                            name: account.name,
                            symbolName: account.symbolName,
                            colorHex: account.colorHex,
                            isSelected: accountIDs.contains(account.id)
                        ) {
                            toggle(account.id, in: &accountIDs)
                        }
                    }
                }
            }

            if !visibleCards.isEmpty {
                Section("Credit Cards") {
                    ForEach(visibleCards) { card in
                        row(
                            name: card.name,
                            symbolName: card.symbolName,
                            colorHex: card.colorHex,
                            isSelected: cardIDs.contains(card.id)
                        ) {
                            toggle(card.id, in: &cardIDs)
                        }
                    }
                }
            }

            Section {
            } footer: {
                Text(accountIDs.isEmpty && cardIDs.isEmpty
                     ? "Nothing ticked, so every account and card counts."
                     : "Only the ticked accounts and cards count towards this budget.")
            }
        }
        .navigationTitle("Accounts & Cards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !accountIDs.isEmpty || !cardIDs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("All") {
                        accountIDs.removeAll()
                        cardIDs.removeAll()
                    }
                }
            }
        }
    }

    private func toggle(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    /// One tickable account or card row.
    private func row(
        name: String,
        symbolName: String,
        colorHex: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CategoryBadge(symbolName: symbolName, colorHex: colorHex)
                Text(name).foregroundStyle(.primary)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
