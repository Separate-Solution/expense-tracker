import SwiftUI
import SwiftData

/// Everything money sits in or is borrowed against: bank accounts and cash on
/// one side, credit cards on the other.
struct AccountsView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortIndex) private var accounts: [Account]
    @Query(sort: \CreditCard.sortIndex) private var cards: [CreditCard]

    @State private var editingAccount: Account?
    @State private var editingCard: CreditCard?
    @State private var isCreatingAccount = false
    @State private var isCreatingCard = false
    @State private var pendingAccountDeletion: Account?
    @State private var pendingCardDeletion: CreditCard?

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }
    private var archivedAccounts: [Account] { accounts.filter(\.isArchived) }
    private var activeCards: [CreditCard] { cards.filter { !$0.isArchived } }
    private var archivedCards: [CreditCard] { cards.filter(\.isArchived) }

    private var hasArchived: Bool { !archivedAccounts.isEmpty || !archivedCards.isEmpty }

    /// What is actually yours: money in accounts less everything owed on cards.
    private var netWorth: Decimal {
        let assets = activeAccounts.reduce(Decimal.zero) { $0 + $1.currentBalance }
        let debts = activeCards.reduce(Decimal.zero) { $0 + $1.outstanding }
        return assets - debts
    }

    var body: some View {
        NavigationStack {
            List {
                if !activeAccounts.isEmpty || !activeCards.isEmpty {
                    Section {
                        HStack {
                            Text("Net balance").font(.subheadline)
                            Spacer()
                            AmountText(amount: netWorth, font: .headline)
                        }
                    } footer: {
                        if !activeCards.isEmpty {
                            Text("Account balances less what is owed on your cards.")
                        }
                    }
                }

                Section("Bank Accounts") {
                    if activeAccounts.isEmpty {
                        EmptyStateView(
                            symbol: "building.columns",
                            title: "No bank accounts",
                            message: "Add your bank accounts and cash to see where money sits."
                        )
                        .listRowBackground(Color.clear)
                    }
                    ForEach(activeAccounts) { account in
                        Button {
                            editingAccount = account
                        } label: {
                            accountRow(account)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingAccountDeletion = account
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                account.isArchived = true
                                try? context.save()
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                }

                Section("Credit Cards") {
                    if activeCards.isEmpty {
                        EmptyStateView(
                            symbol: "creditcard",
                            title: "No credit cards",
                            message: "Add a card to track what you have spent on credit and when the bill is due."
                        )
                        .listRowBackground(Color.clear)
                    }
                    ForEach(activeCards) { card in
                        Button {
                            editingCard = card
                        } label: {
                            cardRow(card)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingCardDeletion = card
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                card.isArchived = true
                                try? context.save()
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(.orange)
                        }
                    }
                }

                if hasArchived {
                    Section("Archived") {
                        ForEach(archivedAccounts) { account in
                            HStack {
                                accountRow(account)
                                Spacer()
                                Button("Restore") {
                                    account.isArchived = false
                                    try? context.save()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }
                        ForEach(archivedCards) { card in
                            HStack {
                                cardRow(card)
                                Spacer()
                                Button("Restore") {
                                    card.isArchived = false
                                    try? context.save()
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New Bank Account", systemImage: "building.columns") {
                            isCreatingAccount = true
                        }
                        Button("New Credit Card", systemImage: "creditcard") {
                            isCreatingCard = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreatingAccount) {
                AccountEditorView(account: nil)
            }
            .sheet(isPresented: $isCreatingCard) {
                CreditCardEditorView(card: nil)
            }
            .sheet(item: $editingAccount) { account in
                AccountEditorView(account: account)
            }
            .sheet(item: $editingCard) { card in
                CreditCardEditorView(card: card)
            }
            .confirmationDialog(
                accountDeletionPrompt,
                isPresented: Binding(
                    get: { pendingAccountDeletion != nil },
                    set: { if !$0 { pendingAccountDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete account and transactions", role: .destructive) {
                    if let pendingAccountDeletion {
                        context.delete(pendingAccountDeletion)
                        try? context.save()
                    }
                    pendingAccountDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingAccountDeletion = nil }
            } message: {
                Text("Archiving keeps the history and hides the account instead.")
            }
            .confirmationDialog(
                cardDeletionPrompt,
                isPresented: Binding(
                    get: { pendingCardDeletion != nil },
                    set: { if !$0 { pendingCardDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete card and transactions", role: .destructive) {
                    if let pendingCardDeletion {
                        context.delete(pendingCardDeletion)
                        try? context.save()
                    }
                    pendingCardDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingCardDeletion = nil }
            } message: {
                Text("Archiving keeps the history and hides the card instead.")
            }
        }
    }

    private var accountDeletionPrompt: String {
        guard let pendingAccountDeletion else { return "Delete account?" }
        let count = pendingAccountDeletion.transactions?.count ?? 0
        return count == 0
            ? "Delete \u{201C}\(pendingAccountDeletion.name)\u{201D}?"
            : "Delete \u{201C}\(pendingAccountDeletion.name)\u{201D} and its \(count) transaction\(count == 1 ? "" : "s")?"
    }

    private var cardDeletionPrompt: String {
        guard let pendingCardDeletion else { return "Delete card?" }
        let count = pendingCardDeletion.transactions?.count ?? 0
        return count == 0
            ? "Delete \u{201C}\(pendingCardDeletion.name)\u{201D}?"
            : "Delete \u{201C}\(pendingCardDeletion.name)\u{201D} and its \(count) transaction\(count == 1 ? "" : "s")?"
    }

    /// Builds one row of the bank accounts list: badge, name, kind and balance.
    /// - Parameter account: The account to render.
    /// - Returns: The configured row view.
    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            AccountBadge(symbolName: account.symbolName, colorHex: account.colorHex)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.body).lineLimit(1)
                Text(account.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            AmountText(amount: account.currentBalance, font: .callout)
        }
        .contentShape(Rectangle())
    }

    /// Builds one row of the credit cards list: what is owed, what is left to
    /// spend, and a nudge when no limit has been entered yet.
    /// - Parameter card: The card to render.
    /// - Returns: The configured row view.
    private func cardRow(_ card: CreditCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                AccountBadge(symbolName: card.symbolName, colorHex: card.colorHex)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name).font(.body).lineLimit(1)
                    Text("Due \(Formatters.ordinalDay(card.dueDay)) \u{00B7} closes \(Formatters.ordinalDay(card.statementDay))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatters.currencyMagnitude(card.outstanding))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(card.outstanding > 0 ? Theme.expense : .primary)
                    Text(card.outstanding > 0 ? "owed" : "clear")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if card.hasCreditLimit {
                CreditUsageBar(card: card)
            } else {
                Text("No credit limit set yet \u{2014} tap to add one.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// The thin bar and caption showing how much of a card's limit is used.
struct CreditUsageBar: View {
    let card: CreditCard

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(Color(hex: card.colorHex))
                        .frame(width: max(2, proxy.size.width * card.utilisation))
                }
            }
            .frame(height: 5)

            HStack {
                Text("\(Formatters.currencyMagnitude(card.availableCredit)) available")
                Spacer()
                Text("of \(Formatters.currencyMagnitude(card.creditLimit))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

struct AccountEditorView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil means "create a new account".
    let account: Account?

    @Query(sort: \Account.sortIndex) private var accounts: [Account]

    @State private var name = ""
    @State private var kind: AccountKind = .bank
    @State private var colorHex = Theme.paletteHexes[0]
    @State private var openingBalance: Decimal = .zero
    @State private var note = ""
    @State private var isShowingAmountPad = false

    private var isNew: Bool { account == nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)

                    Picker("Type", selection: $kind) {
                        ForEach(AccountKind.selectableCases) { option in
                            Label(option.title, systemImage: option.symbolName).tag(option)
                        }
                    }
                }

                Section {
                    Button {
                        isShowingAmountPad = true
                    } label: {
                        HStack {
                            Text("Opening balance").foregroundStyle(.primary)
                            Spacer()
                            Text(Formatters.signedCurrency(openingBalance))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Toggle("Negative (overdrawn)", isOn: Binding(
                        get: { openingBalance < 0 },
                        set: { openingBalance = $0 ? -abs(openingBalance) : abs(openingBalance) }
                    ))
                } footer: {
                    Text("The balance this account had before you started tracking here.")
                }

                Section("Colour") {
                    ColorSwatchPicker(selectedHex: $colorHex)
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(isNew ? "New Bank Account" : "Edit Bank Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .sheet(isPresented: $isShowingAmountPad) {
                OpeningBalanceSheet(value: $openingBalance)
            }
        }
        .onAppear(perform: load)
    }

    /// Fills the form from the account being edited, or picks the next
    /// unused palette colour for a new one.
    private func load() {
        guard let account else {
            colorHex = Theme.paletteHexes[accounts.count % Theme.paletteHexes.count]
            return
        }
        name = account.name
        kind = account.kind
        colorHex = account.colorHex
        openingBalance = account.openingBalance
        note = account.note
    }

    /// Creates or updates the account and dismisses.
    /// An untouched symbol follows the account kind; a customised one is kept.
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let account {
            account.name = trimmed
            // Keep the glyph in step with the type unless it was customised earlier.
            if account.symbolName == account.kind.symbolName { account.symbolName = kind.symbolName }
            account.kind = kind
            account.colorHex = colorHex
            account.openingBalance = openingBalance.roundedToCurrency
            account.note = note
        } else {
            let created = Account(
                name: trimmed,
                kind: kind,
                openingBalance: openingBalance.roundedToCurrency,
                colorHex: colorHex,
                sortIndex: (accounts.map(\.sortIndex).max() ?? -1) + 1,
                note: note
            )
            context.insert(created)
        }
        try? context.save()
        dismiss()
    }
}

/// Calculator sheet that allows a signed value, unlike the transaction one.
private struct OpeningBalanceSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Binding var value: Decimal
    @State private var engine = CalculatorEngine()

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                CalculatorKeypad(engine: $engine, confirmLabel: "Done", confirmEnabled: true) {
                    if let result = engine.result {
                        // Preserve the sign the user picked with the toggle.
                        value = value < 0 ? -abs(result.roundedToCurrency) : result.roundedToCurrency
                    }
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .navigationTitle("Opening Balance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { engine.setValue(abs(value)) }
    }
}
