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
    @State private var date = Date()
    @State private var note = ""
    @State private var amount: Decimal = .zero

    @State private var isShowingAmountPad = false
    @State private var isShowingDeleteConfirmation = false

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

                    // A bill payment only ever moves money out of the account and
                    // off the card. Letting its direction be switched to income
                    // would credit the account while still clearing the debt.
                    if !transaction.isCardPayment {
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

                    // A bill payment isn't spending, so it has no category to
                    // put it under. Offering one would file it in a breakdown
                    // that deliberately ignores it, and let a category filter
                    // surface a row that reads "Card payment".
                    if !transaction.isCardPayment {
                        Picker("Category", selection: $categoryID) {
                            Text("Uncategorized").tag(UUID?.none)
                            ForEach(categories) { category in
                                Label(category.name, systemImage: category.symbol)
                                    .tag(Optional(category.id))
                            }
                        }
                    }

                    // A bill payment always leaves a bank account and always
                    // lands on its card, so only the account is up for change.
                    PaymentSourcePicker(
                        label: transaction.isCardPayment ? "Paid from" : "Paid with",
                        accounts: accounts,
                        cards: transaction.isCardPayment ? [] : cards,
                        allowsNone: !transaction.isCardPayment,
                        selection: $source
                    )

                    DateTimeRow(label: "Date & Time", selection: $date)
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if transaction.isCardPayment, let card = transaction.creditCard {
                    Section {
                        Label("Bill payment to \(card.name)", systemImage: "creditcard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } footer: {
                        Text("This clears card debt rather than being new spending, "
                             + "so it stays out of the month\u{2019}s income and expense totals.")
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
        transaction.type = transaction.isCardPayment ? .expense : type
        transaction.amount = amount.roundedToCurrency
        transaction.date = date
        transaction.note = note
        transaction.category = transaction.isCardPayment
            ? nil
            : allCategories.first { $0.id == categoryID }
        if transaction.isCardPayment {
            // A bill payment's card is fixed; only the paying account can move.
            transaction.account = PaymentSourceResolver.account(source, in: accounts)
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
