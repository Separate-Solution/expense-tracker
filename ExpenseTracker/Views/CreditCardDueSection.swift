import SwiftUI
import SwiftData

/// The dashboard's credit card block: what each card owes from its last closed
/// statement, when that bill is due, and a one-tap way to clear it.
struct CreditCardDueSection: View {

    @Environment(\.modelContext) private var context

    let cards: [CreditCard]
    let accounts: [Account]

    @State private var payingCard: CreditCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Credit Cards")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    cardBlock(card)
                        .padding(.vertical, 10)

                    if index < cards.count - 1 { Divider() }
                }
            }
            .cardBackground()
        }
        .sheet(item: $payingCard) { card in
            CardPaymentSheet(card: card, accounts: accounts)
        }
    }

    /// One card's due summary, with the pay button when there is a bill.
    /// - Parameter card: The card to render.
    /// - Returns: The configured block.
    @ViewBuilder
    private func cardBlock(_ card: CreditCard) -> some View {
        // One instant for the whole block, so a render that straddles midnight
        // can't mix a cycle from one day with a countdown from the next.
        let now = Date.now
        let cycle = card.lastClosedCycle(asOf: now)
        let due = card.amountDue(asOf: now)
        let unbilled = card.currentCycleSpend(asOf: now)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AccountBadge(symbolName: card.symbolName, colorHex: card.colorHex, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name).font(.subheadline).lineLimit(1)
                    Text(dueCaption(cycle: cycle, amountDue: due, asOf: now))
                        .font(.caption)
                        .foregroundStyle(captionTint(cycle: cycle, amountDue: due, asOf: now))
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatters.currencyMagnitude(due))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(due > 0 ? Theme.expense : Theme.income)
                    Text(due > 0 ? "due" : "settled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if card.hasCreditLimit {
                CreditUsageBar(card: card)
            }

            if unbilled > 0 {
                Text("\(Formatters.currencyMagnitude(unbilled)) spent since the last statement, "
                     + "billed on \(card.currentCycle(asOf: now).end.formatted(Formatters.shortDate)).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if due > 0 {
                Button {
                    payingCard = card
                } label: {
                    Label("Pay \(Formatters.currencyMagnitude(due))", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(accounts.isEmpty)

                if accounts.isEmpty {
                    Text("Add a bank account to pay the bill from.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The line under a card's name: when the bill is due, or that it is clear.
    /// - Parameters:
    ///   - cycle: The statement period the bill came from.
    ///   - amountDue: What is still owed on it.
    ///   - date: The instant to measure the countdown from.
    /// - Returns: The caption text.
    private func dueCaption(cycle: BillingCycle, amountDue: Decimal, asOf date: Date) -> String {
        guard amountDue > 0 else {
            return "Nothing due · next bill \(cycle.dueDate.addingMonths(1).formatted(Formatters.shortDate))"
        }
        let days = cycle.daysUntilDue(asOf: date)
        if days < 0 {
            let overdue = -days
            return "Overdue by \(overdue) day\(overdue == 1 ? "" : "s")"
        }
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        return "Due in \(days) days · \(cycle.dueDate.formatted(Formatters.shortDate))"
    }

    /// Red once a bill is overdue or due within three days, secondary otherwise.
    /// - Parameters:
    ///   - cycle: The statement period the bill came from.
    ///   - amountDue: What is still owed on it.
    ///   - date: The instant to measure the countdown from.
    /// - Returns: The colour for the caption.
    private func captionTint(cycle: BillingCycle, amountDue: Decimal, asOf date: Date) -> Color {
        guard amountDue > 0 else { return .secondary }
        return cycle.daysUntilDue(asOf: date) <= 3 ? Theme.expense : .secondary
    }
}

/// Confirms which bank account clears a card's bill, and how much of it.
struct CardPaymentSheet: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let card: CreditCard
    let accounts: [Account]

    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID = ""

    @State private var accountID: UUID?
    @State private var amount: Decimal = .zero
    @State private var date = Date()
    @State private var isShowingAmountPad = false
    @State private var saveFailure: String?

    private var selectedAccount: Account? {
        accounts.first { $0.id == accountID }
    }

    private var amountDue: Decimal { card.amountDue() }

    private var canPay: Bool {
        selectedAccount != nil && amount > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Bill")
                        Spacer()
                        Text(Formatters.currencyMagnitude(amountDue))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Due")
                        Spacer()
                        Text(card.lastClosedCycle().dueDate.formatted(Formatters.shortDate))
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(card.name)
                } footer: {
                    Text("Statement closed on "
                         + "\(card.lastClosedCycle().end.formatted(Formatters.shortDate)).")
                }

                Section {
                    Picker("Pay from", selection: $accountID) {
                        Text("Choose an account").tag(UUID?.none)
                        ForEach(accounts) { account in
                            Label(account.name, systemImage: account.symbolName)
                                .tag(Optional(account.id))
                        }
                    }

                    Button {
                        isShowingAmountPad = true
                    } label: {
                        HStack {
                            Text("Amount").foregroundStyle(.primary)
                            Spacer()
                            Text(Formatters.currencyMagnitude(amount))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    if amount != amountDue, amountDue > 0 {
                        Button("Pay the full bill") { amount = amountDue }
                            .font(.subheadline)
                    }

                    DateTimeRow(label: "Date & Time", selection: $date)
                } footer: {
                    if let selectedAccount, amount > 0 {
                        Text(payoffFooter(for: selectedAccount))
                    }
                }
            }
            .navigationTitle("Pay Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pay", action: pay).disabled(!canPay)
                }
            }
            .sheet(isPresented: $isShowingAmountPad) {
                AmountEntrySheet(amount: $amount, type: .expense)
            }
            .saveFailureAlert($saveFailure)
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: load)
    }

    /// Spells out both sides of the payment before it is made.
    /// - Parameter account: The account the money leaves.
    /// - Returns: The explanatory footer.
    private func payoffFooter(for account: Account) -> String {
        let remaining = max(.zero, (amountDue - amount).roundedToCurrency)
        let base = "\(Formatters.currencyMagnitude(amount)) leaves \(account.name) "
            + "and comes off the card's balance."
        return remaining > 0
            ? base + " \(Formatters.currencyMagnitude(remaining)) of the bill would be left."
            : base
    }

    /// Preselects the full bill and the account last used for a transaction.
    private func load() {
        amount = amountDue
        if case .account(let id) = PaymentSourceResolver.decode(defaultAccountID),
           accounts.contains(where: { $0.id == id }) {
            accountID = id
        } else {
            accountID = accounts.first?.id
        }
    }

    /// Records the payment and closes the sheet.
    private func pay() {
        guard let selectedAccount else { return }
        do {
            try CardPaymentService.pay(
                card: card,
                from: selectedAccount,
                amount: amount,
                date: date,
                in: context
            )
        } catch {
            saveFailure = error.localizedDescription
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
