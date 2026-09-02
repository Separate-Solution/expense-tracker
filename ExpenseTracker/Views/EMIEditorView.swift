import SwiftUI
import SwiftData

/// Creating or editing an EMI. The terms — amount financed, rate, how many
/// payments — suggest the instalment, and the suggestion stays a suggestion:
/// the lender's own figure is the one that gets paid, so it can be typed in.
struct EMIEditorView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil means "create a new plan".
    let plan: EMIPlan?

    @Query(sort: \Category.sortIndex) private var allCategories: [Category]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortIndex)
    private var accounts: [Account]
    @Query(filter: #Predicate<CreditCard> { !$0.isArchived }, sort: \CreditCard.sortIndex)
    private var cards: [CreditCard]

    @State private var title = ""
    @State private var principal: Decimal = .zero
    @State private var interestRate = ""
    @State private var foreclosurePercent = ""
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var isCustomCadence = false
    @State private var interval = 1
    @State private var installmentCount = 12
    @State private var installmentAmount: Decimal = .zero
    /// True once the instalment has been typed in by hand, after which the
    /// terms stop overwriting it — the lender's figure outranks the estimate.
    @State private var hasEditedInstallment = false
    @State private var startDate = Date()
    @State private var categoryID: UUID?
    @State private var source: PaymentSource?
    @State private var note = ""
    @State private var backfillPastInstallments = true
    @State private var isShowingPrincipalPad = false
    @State private var isShowingInstallmentPad = false
    @State private var saveFailure: Error?

    private var isNew: Bool { plan == nil }

    /// Expense categories, plus the one this plan already uses even if it has
    /// since been archived — leaving it out would blank the row and let an
    /// unrelated edit quietly drop the category.
    private var categories: [Category] {
        let visible = allCategories.filter { $0.type == .expense && !$0.isArchived }
        guard let current = plan?.category,
              !visible.contains(where: { $0.id == current.id }) else { return visible }
        return (visible + [current]).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// The unarchived accounts, plus the one this plan already posts into, for
    /// the same reason.
    private var selectableAccounts: [Account] {
        guard let account = plan?.account,
              !accounts.contains(where: { $0.id == account.id }) else { return accounts }
        return (accounts + [account]).sorted { $0.sortIndex < $1.sortIndex }
    }

    /// The unarchived cards, plus the one this plan already charges.
    private var selectableCards: [CreditCard] {
        guard let card = plan?.creditCard,
              !cards.contains(where: { $0.id == card.id }) else { return cards }
        return (cards + [card]).sorted { $0.sortIndex < $1.sortIndex }
    }

    private var rateValue: Decimal { Decimal(percentInput: interestRate) ?? .zero }
    private var foreclosureValue: Decimal { Decimal(percentInput: foreclosurePercent) ?? .zero }

    /// Interest for one instalment period, from the annual rate and the cadence.
    private var periodRate: Double {
        let periods = frequency.periodsPerYear / Double(max(1, effectiveInterval))
        guard periods > 0 else { return 0 }
        return (rateValue.doubleValue / 100) / periods
    }

    /// Only a custom cadence carries an interval; the named ones are every one
    /// of their unit.
    private var effectiveInterval: Int { isCustomCadence ? interval : 1 }

    private var suggestedInstallment: Decimal {
        EMIPlan.suggestedInstallment(
            principal: principal,
            periodRate: periodRate,
            count: installmentCount
        )
    }

    /// Everything the plan would cost at the instalment currently entered.
    private var totalPayable: Decimal {
        (installmentAmount * Decimal(installmentCount)).roundedToCurrency
    }

    private var canSave: Bool {
        principal > 0
            && installmentAmount > 0
            && installmentCount > 0
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $title)

                    Button {
                        isShowingPrincipalPad = true
                    } label: {
                        HStack {
                            Text("Amount financed").foregroundStyle(.primary)
                            Spacer()
                            AmountText(amount: principal, type: .expense, font: .title3)
                        }
                    }

                    LabeledContent("Interest rate") {
                        HStack(spacing: 4) {
                            TextField("0", text: $interestRate)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("% a year").foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("Leave the rate at 0 for a no-cost EMI, where the instalments only divide the amount up.")
                }

                Section("Schedule") {
                    Picker("Frequency", selection: cadenceBinding) {
                        ForEach(RecurrenceFrequency.allCases) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                        Text("Custom").tag(customTag)
                    }
                    if isCustomCadence {
                        Picker("Repeats by", selection: $frequency) {
                            ForEach(RecurrenceFrequency.allCases) { option in
                                Text(option.unitLabel(interval: 1).capitalized).tag(option)
                            }
                        }
                        Stepper("Every \(interval) \(frequency.unitLabel(interval: interval))",
                                value: $interval, in: 1...30)
                    }
                    Stepper("\(installmentCount) instalments", value: $installmentCount, in: 1...600)
                    DatePicker("First instalment", selection: $startDate, displayedComponents: .date)
                    if isNew && startDate < Date.now.startOfDay {
                        Toggle("Post the instalments already due", isOn: $backfillPastInstallments)
                    }
                }

                Section {
                    Button {
                        isShowingInstallmentPad = true
                    } label: {
                        HStack {
                            Text("Instalment").foregroundStyle(.primary)
                            Spacer()
                            AmountText(amount: installmentAmount, type: .expense, font: .title3)
                        }
                    }
                    if hasEditedInstallment && suggestedInstallment > 0
                        && suggestedInstallment != installmentAmount {
                        Button("Use suggested \(Formatters.currencyMagnitude(suggestedInstallment))") {
                            installmentAmount = suggestedInstallment
                            hasEditedInstallment = false
                        }
                        .font(.callout)
                    }
                    LabeledContent("Total payable", value: Formatters.currencyMagnitude(totalPayable))
                    LabeledContent("Interest",
                                   value: Formatters.currencyMagnitude(max(.zero, totalPayable - principal)))
                } header: {
                    Text("Instalment")
                } footer: {
                    Text("Suggested on a reducing balance from the amount, rate and number of instalments. Edit it to match what the lender actually charges.")
                }

                Section {
                    LabeledContent("Foreclosure charge") {
                        HStack(spacing: 4) {
                            TextField("0", text: $foreclosurePercent)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("% of principal").foregroundStyle(.secondary)
                        }
                    }
                    PaymentSourcePicker(
                        accounts: selectableAccounts,
                        cards: selectableCards,
                        selection: $source
                    )
                    Picker("Category", selection: $categoryID) {
                        Text("Uncategorized").tag(UUID?.none)
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.symbol).tag(Optional(category.id))
                        }
                    }
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Details")
                } footer: {
                    Text("Charged to a card, each instalment lands on that card's bill and counts as paid once the bill is cleared.")
                }

                if let plan, !isNew {
                    Section {
                        LabeledContent("Paid so far", value: "\(plan.paidCount()) of \(plan.installmentCount)")
                    } footer: {
                        Text("Changing the schedule only affects instalments that haven't fallen due yet.")
                    }
                }
            }
            .navigationTitle(isNew ? "New EMI" : "Edit EMI")
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
            .sheet(isPresented: $isShowingPrincipalPad) {
                AmountEntrySheet(amount: $principal, type: .expense)
            }
            .sheet(isPresented: $isShowingInstallmentPad) {
                AmountEntrySheet(amount: $installmentAmount, type: .expense)
            }
            .onChange(of: installmentAmount) { _, newValue in
                // Anything that isn't the current suggestion came from the pad.
                if newValue != suggestedInstallment { hasEditedInstallment = true }
            }
            .onChange(of: principal) { _, _ in refreshSuggestion() }
            .onChange(of: interestRate) { _, _ in refreshSuggestion() }
            .onChange(of: installmentCount) { _, _ in refreshSuggestion() }
            .onChange(of: frequency) { _, _ in refreshSuggestion() }
            .onChange(of: interval) { _, _ in refreshSuggestion() }
            .onChange(of: isCustomCadence) { _, _ in refreshSuggestion() }
        }
        .onAppear(perform: load)
    }

    /// The tag standing for a custom cadence, which no frequency uses.
    private var customTag: String { "custom" }

    /// One picker over both the named cadences and "Custom", which is a
    /// frequency plus an interval rather than a frequency of its own.
    private var cadenceBinding: Binding<String> {
        Binding(
            get: { isCustomCadence ? customTag : frequency.rawValue },
            set: { newValue in
                if newValue == customTag {
                    isCustomCadence = true
                } else {
                    isCustomCadence = false
                    interval = 1
                    frequency = RecurrenceFrequency(rawValue: newValue) ?? .monthly
                }
            }
        )
    }

    /// Keeps the instalment in step with the terms until it is typed in by hand.
    private func refreshSuggestion() {
        guard !hasEditedInstallment else { return }
        installmentAmount = suggestedInstallment
    }

    /// Fills the form from the plan being edited, or defaults a new one to the
    /// preferred payment source.
    private func load() {
        guard let plan else {
            source = accounts.first.map { .account($0.id) }
            return
        }
        title = plan.title
        principal = plan.principal
        interestRate = plan.annualInterestRate > 0 ? "\(plan.annualInterestRate)" : ""
        foreclosurePercent = plan.foreclosureChargePercent > 0 ? "\(plan.foreclosureChargePercent)" : ""
        frequency = plan.frequency
        interval = plan.interval
        isCustomCadence = plan.interval > 1
        installmentCount = plan.installmentCount
        installmentAmount = plan.installmentAmount
        // An existing plan's instalment is whatever it was saved with, so it is
        // never overwritten by a suggestion drawn from the same terms.
        hasEditedInstallment = true
        startDate = plan.startDate
        categoryID = plan.category?.id
        source = plan.paymentSource
        note = plan.note
    }

    /// Creates or updates the plan, posts whatever is already due, and dismisses.
    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = allCategories.first { $0.id == categoryID }
        let account = PaymentSourceResolver.account(source, in: selectableAccounts)
        let card = PaymentSourceResolver.card(source, in: selectableCards)

        if let plan {
            plan.title = trimmed
            plan.principal = principal.roundedToCurrency
            plan.annualInterestRate = max(.zero, rateValue)
            plan.foreclosureChargePercent = max(.zero, foreclosureValue)
            plan.frequency = frequency
            plan.interval = effectiveInterval
            plan.installmentCount = max(1, installmentCount)
            plan.installmentAmount = installmentAmount.roundedToCurrency
            plan.startDate = startDate.startOfDay
            plan.category = category
            plan.account = account
            plan.creditCard = card
            plan.note = note
            EMIEngine.applyEdits(of: plan, in: context)
        } else {
            let created = EMIPlan(
                title: trimmed,
                principal: principal.roundedToCurrency,
                annualInterestRate: rateValue,
                foreclosureChargePercent: foreclosureValue,
                frequency: frequency,
                interval: effectiveInterval,
                installmentCount: installmentCount,
                installmentAmount: installmentAmount.roundedToCurrency,
                startDate: startDate,
                note: note,
                account: account,
                creditCard: card,
                category: category
            )
            context.insert(created)
            if !backfillPastInstallments && startDate < Date.now.startOfDay {
                // Nothing before today is written into history, but the plan
                // still counts those instalments as paid — they were, before it
                // was added — so it can still reach its own end.
                EMIEngine.skipInstallmentsAlreadyDue(for: created)
            }
        }

        if let failure = context.saveReportingFailure() {
            saveFailure = failure
            return
        }
        EMIEngine.postDueInstallments(in: context)
        dismiss()
    }
}
