import SwiftUI
import SwiftData

/// Edit or delete an existing transaction. Amount changes reuse the calculator.
struct TransactionEditorView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let transaction: Transaction

    @Query(sort: \Category.sortIndex) private var allCategories: [Category]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortIndex)
    private var accounts: [Account]
    @Query(filter: #Predicate<CreditCard> { !$0.isArchived }, sort: \CreditCard.sortIndex)
    private var cards: [CreditCard]

    @State private var title = ""
    @State private var type: TransactionType = .expense
    @State private var categoryID: UUID?
    @State private var source: PaymentSource?
    /// The other end of a transfer.
    @State private var destinationID: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var amount: Decimal = .zero

    @State private var isShowingAmountPad = false
    @State private var isShowingDeleteConfirmation = false

    private var categories: [Category] {
        allCategories.filter { $0.type == type && !$0.isArchived }
    }

    private var canSave: Bool {
        guard amount > 0, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard transaction.isTransfer else { return true }
        // Both ends have to exist and differ, or the money would land nowhere
        // or come straight back to where it started.
        let sourceID = PaymentSourceResolver.account(source, in: accounts)?.id
        return sourceID != nil && destinationID != nil && sourceID != destinationID
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isShowingAmountPad = true
                    } label: {
                        HStack {
                            Text("Amount")
                                .foregroundStyle(.primary)
                            Spacer()
                            AmountText(amount: amount, type: type, font: .title3)
                        }
                    }

                    // A movement only ever leaves its source; the other end picks
                    // it up. Letting the direction be switched to income would
                    // credit both sides at once, inventing money.
                    if !transaction.isMovement {
                        Picker("Type", selection: $type) {
                            ForEach(TransactionType.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: type) { _, newValue in
                            // Keep the category consistent with the new direction.
                            if let categoryID,
                               allCategories.first(where: { $0.id == categoryID })?.type != newValue {
                                self.categoryID = nil
                            }
                        }
                    }
                }

                Section("Details") {
                    TextField("Title", text: $title)

                    // A movement isn't spending, so it has no category to put it
                    // under. Offering one would file it in a breakdown that
                    // deliberately ignores it, and let a category filter surface
                    // a row that reads "Transfer".
                    if !transaction.isMovement {
                        Picker("Category", selection: $categoryID) {
                            Text("Uncategorized").tag(UUID?.none)
                            ForEach(categories) { category in
                                Label(category.name, systemImage: category.symbol)
                                    .tag(Optional(category.id))
                            }
                        }
                    }

                    // A movement always leaves an account, so its source is never
                    // "none" and never a card. A bill payment's card is fixed;
                    // a transfer's destination can be changed below.
                    PaymentSourcePicker(
                        label: transaction.isMovement ? "From" : "Paid with",
                        accounts: accounts,
                        cards: transaction.isMovement ? [] : cards,
                        allowsNone: !transaction.isMovement,
                        selection: $source
                    )

                    if transaction.isTransfer {
                        Picker("To", selection: $destinationID) {
                            Text("Choose an account").tag(UUID?.none)
                            ForEach(accounts.filter { account in
                                PaymentSourceResolver.account(source, in: accounts)?.id != account.id
                            }) { account in
                                Label(account.name, systemImage: account.symbolName)
                                    .tag(Optional(account.id))
                            }
                        }
                    }

                    DateTimeRow(label: "Date & Time", selection: $date)
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if transaction.isMovement {
                    Section {
                        Label(
                            transaction.movementSummary ?? transaction.kind.title,
                            systemImage: transaction.kind.symbolName
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } footer: {
                        Text(transaction.isCardPayment
                             ? "This clears card debt rather than being new spending, "
                               + "so it stays out of the month\u{2019}s income and expense totals."
                             : "This moves money between your own accounts, so it stays out of "
                               + "the month\u{2019}s income and expense totals and leaves your "
                               + "net worth unchanged.")
                    }
                }

                if let rule = transaction.recurringRule {
                    Section {
                        Label("Created by “\(rule.title)” · \(rule.summary)", systemImage: "repeat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } footer: {
                        Text("Editing this one occurrence won't change the repeating rule.")
                    }
                }

                Section {
                    Button("Delete Transaction", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Edit")
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
                AmountEntrySheet(amount: $amount, type: type)
            }
            .confirmationDialog("Delete this transaction?",
                                isPresented: $isShowingDeleteConfirmation,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    context.delete(transaction)
                    try? context.save()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
        .onAppear(perform: load)
    }

    /// Copies the transaction's stored values into the form's local state.
    /// Runs on appear so editing always starts from what is persisted.
    private func load() {
        title = transaction.title
        type = transaction.type
        categoryID = transaction.category?.id
        source = transaction.paymentSource
        destinationID = transaction.toAccount?.id
        date = transaction.date
        note = transaction.note
        amount = transaction.amount
    }

    /// Writes the form back to the transaction, stamps `updatedAt`, saves
    /// and dismisses. The title is trimmed and the amount rounded first.
    private func save() {
        transaction.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Belt and braces alongside hiding the picker: a payment is an expense
        // on the account it leaves, whatever state the form was left in.
        transaction.type = transaction.isMovement ? .expense : type
        transaction.amount = amount.roundedToCurrency
        transaction.date = date
        transaction.note = note
        transaction.category = transaction.isMovement
            ? nil
            : allCategories.first { $0.id == categoryID }
        if transaction.isCardPayment {
            // A bill payment's card is fixed; only the paying account can move.
            transaction.account = PaymentSourceResolver.account(source, in: accounts)
        } else if transaction.isTransfer {
            transaction.account = PaymentSourceResolver.account(source, in: accounts)
            transaction.toAccount = accounts.first { $0.id == destinationID }
        } else {
            transaction.account = PaymentSourceResolver.account(source, in: accounts)
            transaction.creditCard = PaymentSourceResolver.card(source, in: cards)
        }
        transaction.updatedAt = Date()
        try? context.save()
        dismiss()
    }
}

/// Standalone calculator sheet used wherever an amount needs editing.
struct AmountEntrySheet: View {

    @Environment(\.dismiss) private var dismiss

    @Binding var amount: Decimal
    var type: TransactionType

    @State private var engine = CalculatorEngine()

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                CalculatorKeypad(
                    engine: $engine,
                    tint: type.tint,
                    confirmLabel: "Done",
                    confirmEnabled: (engine.result ?? .zero) > 0
                ) {
                    if let value = engine.result {
                        amount = value.roundedToCurrency
                    }
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .navigationTitle("Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { engine.setValue(amount) }
    }
}
