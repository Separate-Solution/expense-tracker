import SwiftUI
import SwiftData

struct AccountsView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortIndex) private var accounts: [Account]

    @State private var editingAccount: Account?
    @State private var isCreating = false
    @State private var pendingDeletion: Account?

    private var activeAccounts: [Account] { accounts.filter { !$0.isArchived } }
    private var archivedAccounts: [Account] { accounts.filter(\.isArchived) }

    /// Assets minus what is owed on credit cards.
    private var netWorth: Decimal {
        activeAccounts.reduce(Decimal.zero) { $0 + $1.currentBalance }
    }

    var body: some View {
        NavigationStack {
            List {
                if !activeAccounts.isEmpty {
                    Section {
                        HStack {
                            Text("Net balance").font(.subheadline)
                            Spacer()
                            AmountText(amount: netWorth, font: .headline)
                        }
                    }
                }

                Section("Accounts") {
                    if activeAccounts.isEmpty {
                        EmptyStateView(
                            symbol: "creditcard",
                            title: "No accounts",
                            message: "Add your bank accounts, credit cards and cash to see where money sits."
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
                                pendingDeletion = account
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

                if !archivedAccounts.isEmpty {
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
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreating) {
                AccountEditorView(account: nil)
            }
            .sheet(item: $editingAccount) { account in
                AccountEditorView(account: account)
            }
            .confirmationDialog(
                deletionPrompt,
                isPresented: Binding(
                    get: { pendingDeletion != nil },
                    set: { if !$0 { pendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete account and transactions", role: .destructive) {
                    if let pendingDeletion {
                        context.delete(pendingDeletion)
                        try? context.save()
                    }
                    pendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingDeletion = nil }
            } message: {
                Text("Archiving keeps the history and hides the account instead.")
            }
        }
    }

    private var deletionPrompt: String {
        guard let pendingDeletion else { return "Delete account?" }
        let count = pendingDeletion.transactions?.count ?? 0
        return count == 0
            ? "Delete “\(pendingDeletion.name)”?"
            : "Delete “\(pendingDeletion.name)” and its \(count) transaction\(count == 1 ? "" : "s")?"
    }

    /// Builds one row of the accounts list: badge, name, kind and balance.
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
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(amount: account.currentBalance, font: .callout)
                if account.kind.isLiability, account.currentBalance < 0 {
                    Text("owed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
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
                        ForEach(AccountKind.allCases) { option in
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
                    Toggle("Negative (money owed)", isOn: Binding(
                        get: { openingBalance < 0 },
                        set: { openingBalance = $0 ? -abs(openingBalance) : abs(openingBalance) }
                    ))
                } footer: {
                    Text(kind == .credit
                         ? "For a credit card, enter what you currently owe and switch on “money owed”."
                         : "The balance this account had before you started tracking here.")
                }

                Section("Colour") {
                    ColorSwatchPicker(selectedHex: $colorHex)
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(isNew ? "New Account" : "Edit Account")
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
