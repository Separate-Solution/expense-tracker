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

    @State private var title = ""
    @State private var type: TransactionType = .expense
    @State private var categoryID: UUID?
    @State private var accountID: UUID?
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

                Section("Details") {
                    TextField("Title", text: $title)

                    Picker("Category", selection: $categoryID) {
                        Text("Uncategorized").tag(UUID?.none)
                        ForEach(categories) { category in
                            Text("\(category.emoji)  \(category.name)").tag(Optional(category.id))
                        }
                    }

                    Picker("Account", selection: $accountID) {
                        Text("None").tag(UUID?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(2...5)
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
        accountID = transaction.account?.id
        date = transaction.date
        note = transaction.note
        amount = transaction.amount
    }

    /// Writes the form back to the transaction, stamps `updatedAt`, saves
    /// and dismisses. The title is trimmed and the amount rounded first.
    private func save() {
        transaction.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.type = type
        transaction.amount = amount.roundedToCurrency
        transaction.date = date
        transaction.note = note
        transaction.category = allCategories.first { $0.id == categoryID }
        transaction.account = accounts.first { $0.id == accountID }
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
