import SwiftUI
import SwiftData

struct SubscriptionsView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringRule.title) private var rules: [RecurringRule]

    @State private var editingRule: RecurringRule?
    @State private var isCreating = false
    @State private var pendingDeletion: RecurringRule?
    @State private var saveFailure: String?

    private var activeRules: [RecurringRule] { rules.filter(\.isActive) }
    private var pausedRules: [RecurringRule] { rules.filter { !$0.isActive } }

    /// Rough monthly cost of every active expense rule, normalised across frequencies.
    private var estimatedMonthlyOutgoing: Decimal {
        activeRules
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + monthlyEquivalent(of: $1) }
    }

    /// Normalises a rule's cost to a per-month figure so cadences can be
    /// totalled together. Weeks use 4.345 (52 ÷ 12) and days use 30.
    /// - Parameter rule: The rule to convert.
    /// - Returns: Approximate monthly cost.
    private func monthlyEquivalent(of rule: RecurringRule) -> Decimal {
        let perPeriod = rule.amount / Decimal(max(1, rule.interval))
        switch rule.frequency {
        case .daily: return perPeriod * 30
        case .weekly: return perPeriod * Decimal(string: "4.345")!
        case .monthly: return perPeriod
        case .yearly: return perPeriod / 12
        }
    }

    var body: some View {
        List {
            if !activeRules.isEmpty {
                Section {
                    HStack {
                        Text("Roughly per month").font(.subheadline)
                        Spacer()
                        Text(Formatters.currencyMagnitude(estimatedMonthlyOutgoing.roundedToCurrency))
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.expense)
                    }
                } footer: {
                    Text("Weekly and yearly amounts are converted to a monthly average.")
                }
            }

            Section("Active") {
                if activeRules.isEmpty {
                    EmptyStateView(
                        symbol: "repeat",
                        title: "No recurring transactions",
                        message: "Subscriptions, rent, salary and EMIs can post themselves automatically."
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(activeRules) { rule in
                    ruleRow(rule)
                }
            }

            if !pausedRules.isEmpty {
                Section("Paused") {
                    ForEach(pausedRules) { rule in
                        ruleRow(rule)
                    }
                }
            }
        }
        .navigationTitle("Recurring")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isCreating = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $isCreating) {
            RecurringRuleEditorView(rule: nil)
        }
        .sheet(item: $editingRule) { rule in
            RecurringRuleEditorView(rule: rule)
        }
        .confirmationDialog(
            "Delete this recurring rule?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete rule, keep history", role: .destructive) {
                if let pendingDeletion {
                    context.delete(pendingDeletion)
                    saveFailure = context.saveReportingFailure()
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Transactions it already created stay in your history.")
        }
        .saveFailureAlert($saveFailure)
    }

    /// Builds one row of the subscriptions list, with its swipe actions.
    /// - Parameter rule: The rule to render.
    /// - Returns: The configured row view.
    private func ruleRow(_ rule: RecurringRule) -> some View {
        Button {
            editingRule = rule
        } label: {
            HStack(spacing: 12) {
                CategoryBadge(
                    symbolName: rule.category?.symbol ?? CategoryIcon.recurringFallback,
                    colorHex: rule.category?.colorHex ?? Theme.paletteHexes[5]
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.title).foregroundStyle(.primary).lineLimit(1)
                    Text(subtitle(for: rule))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                AmountText(amount: rule.amount, type: rule.type, font: .callout)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDeletion = rule
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                rule.isActive.toggle()
                if let failure = context.saveReportingFailure() {
                    rule.isActive.toggle()
                    saveFailure = failure
                } else if rule.isActive {
                    RecurrenceEngine.postDueTransactions(in: context)
                }
            } label: {
                Label(rule.isActive ? "Pause" : "Resume",
                      systemImage: rule.isActive ? "pause" : "play")
            }
            .tint(.orange)
        }
    }

    /// Cadence plus status — paused, finished, or when it next posts.
    /// - Parameter rule: The rule to describe.
    /// - Returns: E.g. "Every month · next Tomorrow".
    private func subtitle(for rule: RecurringRule) -> String {
        guard rule.isActive else { return "\(rule.summary) · paused" }
        guard let next = rule.nextOccurrence() else { return "\(rule.summary) · finished" }
        return "\(rule.summary) · next \(Formatters.relativeDayLabel(for: next))"
    }
}

struct RecurringRuleEditorView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil means "create a new rule".
    let rule: RecurringRule?

    @Query(sort: \Category.sortIndex) private var allCategories: [Category]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortIndex)
    private var accounts: [Account]
    @Query(filter: #Predicate<CreditCard> { !$0.isArchived }, sort: \CreditCard.sortIndex)
    private var cards: [CreditCard]

    @State private var title = ""
    @State private var amount: Decimal = .zero
    @State private var type: TransactionType = .expense
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var interval = 1
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date().addingMonths(12)
    @State private var categoryID: UUID?
    @State private var source: PaymentSource?
    @State private var note = ""
    @State private var backfillPastOccurrences = true
    @State private var isShowingAmountPad = false
    @State private var saveFailure: String?

    private var isNew: Bool { rule == nil }

    private var categories: [Category] {
        allCategories.filter { $0.type == type && !$0.isArchived }
    }

    private var canSave: Bool {
        amount > 0 && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $title)

                    Button {
                        isShowingAmountPad = true
                    } label: {
                        HStack {
                            Text("Amount").foregroundStyle(.primary)
                            Spacer()
                            AmountText(amount: amount, type: type, font: .title3)
                        }
                    }

                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: type) { _, newValue in
                        if let categoryID,
                           allCategories.first(where: { $0.id == categoryID })?.type != newValue {
                            self.categoryID = nil
                        }
                    }
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Stepper("Every \(interval) \(frequency.unitLabel(interval: interval))",
                            value: $interval, in: 1...30)
                    DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                    Toggle("Has an end date", isOn: $hasEndDate.animation())
                    if hasEndDate {
                        DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                    if isNew && startDate < Date.now.startOfDay {
                        Toggle("Backfill past occurrences", isOn: $backfillPastOccurrences)
                    }
                }

                Section("Details") {
                    Picker("Category", selection: $categoryID) {
                        Text("Uncategorized").tag(UUID?.none)
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.symbol).tag(Optional(category.id))
                        }
                    }
                    PaymentSourcePicker(accounts: accounts, cards: cards, selection: $source)
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                if let rule {
                    Section {
                        LabeledContent("Posted so far", value: "\(rule.transactions?.count ?? 0)")
                        if let next = rule.nextOccurrence() {
                            LabeledContent("Next", value: next.formatted(Formatters.shortDate))
                        }
                    } footer: {
                        Text("Changing the schedule only affects occurrences that haven't posted yet.")
                    }
                }
            }
            .navigationTitle(isNew ? "New Recurring" : "Edit Recurring")
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
                AmountEntrySheet(amount: $amount, type: type)
            }
        }
        .onAppear(perform: load)
    }

    /// Fills the form from the rule being edited, or defaults a new rule to
    /// the first bank account with a one-year end date ready to enable.
    private func load() {
        guard let rule else {
            source = accounts.first.map { .account($0.id) }
            return
        }
        title = rule.title
        amount = rule.amount
        type = rule.type
        frequency = rule.frequency
        interval = rule.interval
        startDate = rule.startDate
        hasEndDate = rule.endDate != nil
        endDate = rule.endDate ?? Date().addingMonths(12)
        categoryID = rule.category?.id
        source = rule.paymentSource
        note = rule.note
    }

    /// Creates or updates the rule and dismisses.
    /// Editing rewrites not-yet-due generated transactions via
    /// `RecurrenceEngine.applyEdits(of:in:)`; history is left alone.
    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = allCategories.first { $0.id == categoryID }
        let account = PaymentSourceResolver.account(source, in: accounts)
        let card = PaymentSourceResolver.card(source, in: cards)

        if let rule {
            rule.title = trimmed
            rule.amount = amount.roundedToCurrency
            rule.type = type
            rule.frequency = frequency
            rule.interval = interval
            rule.startDate = startDate.startOfDay
            rule.endDate = hasEndDate ? endDate.endOfDay : nil
            rule.category = category
            rule.account = account
            rule.creditCard = card
            rule.note = note
            RecurrenceEngine.applyEdits(of: rule, in: context)
        } else {
            let created = RecurringRule(
                title: trimmed,
                amount: amount.roundedToCurrency,
                type: type,
                frequency: frequency,
                interval: interval,
                startDate: startDate,
                endDate: hasEndDate ? endDate : nil,
                note: note,
                account: account,
                creditCard: card,
                category: category
            )
            context.insert(created)
            if !backfillPastOccurrences && startDate < Date.now.startOfDay {
                RecurrenceEngine.skipOccurrences(for: created)
            }
        }

        if let failure = context.saveReportingFailure() {
            saveFailure = failure
            return
        }
        RecurrenceEngine.postDueTransactions(in: context)
        dismiss()
    }
}
