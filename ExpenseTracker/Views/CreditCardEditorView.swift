import SwiftUI
import SwiftData

/// Create or edit a credit card: its limit, its billing cycle and what is
/// already owed on it.
struct CreditCardEditorView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil means "create a new card".
    let card: CreditCard?

    @Query(sort: \CreditCard.sortIndex) private var cards: [CreditCard]

    @State private var name = ""
    @State private var creditLimit: Decimal = .zero
    @State private var statementDay = 1
    @State private var dueDay = 20
    @State private var openingOutstanding: Decimal = .zero
    @State private var colorHex = Theme.paletteHexes[0]
    @State private var note = ""
    @State private var editingAmount: AmountField?

    /// Which of the two money fields the calculator sheet is editing.
    private enum AmountField: String, Identifiable {
        case creditLimit, outstanding
        var id: String { rawValue }

        var title: String {
            switch self {
            case .creditLimit: return "Credit Limit"
            case .outstanding: return "Amount Owed"
            }
        }
    }

    private var isNew: Bool { card == nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The cycle the entered days describe, so the footer can show real dates
    /// rather than making the user work them out.
    private var previewCycle: BillingCycle {
        BillingCycle.lastClosed(statementDay: statementDay, dueDay: dueDay)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                }

                Section {
                    amountRow(
                        "Credit limit",
                        value: creditLimit,
                        placeholder: "Not set",
                        field: .creditLimit
                    )
                } footer: {
                    Text(creditLimit > 0
                         ? "Available credit counts down from here as you spend."
                         : "Add the limit to see how much credit you have left.")
                }

                Section {
                    Picker("Statement closes", selection: $statementDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text(Formatters.ordinalDay(day)).tag(day)
                        }
                    }
                    Picker("Payment due", selection: $dueDay) {
                        ForEach(1...31, id: \.self) { day in
                            Text(Formatters.ordinalDay(day)).tag(day)
                        }
                    }
                } header: {
                    Text("Billing cycle")
                } footer: {
                    Text(cycleFooter)
                }

                Section {
                    amountRow(
                        "Already owed",
                        value: openingOutstanding,
                        placeholder: "Nothing",
                        field: .outstanding
                    )
                } footer: {
                    Text("What you owe on the card today, before anything logged in this app.")
                }

                Section("Colour") {
                    ColorSwatchPicker(selectedHex: $colorHex)
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(isNew ? "New Credit Card" : "Edit Credit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .sheet(item: $editingAmount) { field in
                CardAmountSheet(
                    title: field.title,
                    value: field == .creditLimit ? $creditLimit : $openingOutstanding
                )
            }
        }
        .onAppear(perform: load)
    }

    private var cycleFooter: String {
        let cycle = previewCycle
        let close = cycle.end.formatted(Formatters.shortDate)
        let due = cycle.dueDate.formatted(Formatters.shortDate)
        return "Spending between the \(Formatters.ordinalDay(statementDay)) of one month and the "
            + "\(Formatters.ordinalDay(statementDay)) of the next is billed together. "
            + "The statement that closed on \(close) is due on \(due)."
    }

    /// A tappable money row that opens the calculator.
    /// - Parameters:
    ///   - label: Row title.
    ///   - value: Current value, shown on the right.
    ///   - placeholder: Shown instead of a zero value.
    ///   - field: Which field the sheet should edit.
    /// - Returns: The configured row.
    private func amountRow(
        _ label: String,
        value: Decimal,
        placeholder: String,
        field: AmountField
    ) -> some View {
        Button {
            editingAmount = field
        } label: {
            HStack {
                Text(label).foregroundStyle(.primary)
                Spacer()
                Text(value > 0 ? Formatters.currencyMagnitude(value) : placeholder)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Fills the form from the card being edited, or picks the next unused
    /// palette colour for a new one.
    private func load() {
        guard let card else {
            colorHex = Theme.paletteHexes[cards.count % Theme.paletteHexes.count]
            return
        }
        name = card.name
        creditLimit = card.creditLimit
        statementDay = card.statementDay
        dueDay = card.dueDay
        openingOutstanding = card.openingOutstanding
        colorHex = card.colorHex
        note = card.note
    }

    /// Creates or updates the card and dismisses.
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let card {
            card.name = trimmed
            card.creditLimit = max(.zero, creditLimit.roundedToCurrency)
            card.statementDay = BillingCycle.clampDayOfMonth(statementDay)
            card.dueDay = BillingCycle.clampDayOfMonth(dueDay)
            card.openingOutstanding = openingOutstanding.roundedToCurrency
            card.colorHex = colorHex
            card.note = note
        } else {
            let created = CreditCard(
                name: trimmed,
                creditLimit: creditLimit.roundedToCurrency,
                statementDay: statementDay,
                dueDay: dueDay,
                openingOutstanding: openingOutstanding.roundedToCurrency,
                colorHex: colorHex,
                sortIndex: (cards.map(\.sortIndex).max() ?? -1) + 1,
                note: note
            )
            context.insert(created)
        }
        try? context.save()
        dismiss()
    }
}

/// Calculator sheet for the card's limit and opening balance, both of which are
/// unsigned — a card's debt is tracked as a positive number.
private struct CardAmountSheet: View {

    @Environment(\.dismiss) private var dismiss

    let title: String
    @Binding var value: Decimal

    @State private var engine = CalculatorEngine()

    var body: some View {
        NavigationStack {
            VStack {
                Spacer(minLength: 0)
                CalculatorKeypad(engine: $engine, confirmLabel: "Done", confirmEnabled: true) {
                    if let result = engine.result {
                        value = max(.zero, result.roundedToCurrency)
                    }
                    dismiss()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { engine.setValue(value) }
    }
}
