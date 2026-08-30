import SwiftUI
import SwiftData

/// Moves money between two accounts. Deliberately shaped like the card bill
/// payment sheet: pick both ends, pick an amount, and the app writes one row.
struct TransferSheet: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// Preselected source, when opened from a particular account's row.
    var initialSource: Account?

    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortIndex)
    private var accounts: [Account]

    @State private var sourceID: UUID?
    @State private var destinationID: UUID?
    @State private var amount: Decimal = .zero
    @State private var date = Date()
    @State private var note = ""
    @State private var isShowingAmountPad = false
    @State private var errorMessage: String?

    private var source: Account? { accounts.first { $0.id == sourceID } }
    private var destination: Account? { accounts.first { $0.id == destinationID } }

    private var canTransfer: Bool {
        source != nil && destination != nil && sourceID != destinationID && amount > 0
    }

    /// Two accounts are the minimum for this to mean anything.
    private var hasEnoughAccounts: Bool { accounts.count >= 2 }

    var body: some View {
        NavigationStack {
            Group {
                if hasEnoughAccounts {
                    form
                } else {
                    EmptyStateView(
                        symbol: "arrow.left.arrow.right",
                        title: "Two accounts needed",
                        message: "Add another bank account or cash to move money between them."
                    )
                    .padding(.horizontal, 24)
                }
            }
            .navigationTitle("Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Transfer", action: save)
                        .disabled(!canTransfer)
                }
            }
            .sheet(isPresented: $isShowingAmountPad) {
                AmountEntrySheet(amount: $amount, type: .expense)
            }
            .alert("Couldn't transfer", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: load)
    }

    private var form: some View {
        Form {
            Section {
                accountPicker("From", selection: $sourceID, excluding: destinationID)
                accountPicker("To", selection: $destinationID, excluding: sourceID)

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

                DateTimeRow(label: "Date & Time", selection: $date)
            } footer: {
                if let summary = balanceSummary {
                    Text(summary)
                }
            }

            Section("Note") {
                TextField("Optional", text: $note, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                Label(
                    "A transfer isn't income or spending, so it won't change your"
                    + " net worth or this month's totals.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Spells out both balances after the move, so an overdraft is visible
    /// before it happens rather than after.
    private var balanceSummary: String? {
        guard let source, let destination, amount > 0 else { return nil }
        let after = source.currentBalance - amount
        let landing = destination.currentBalance + amount
        var text = "\(source.name) goes to \(Formatters.balance(after)), "
            + "\(destination.name) to \(Formatters.balance(landing))."
        if after < 0 {
            text += " That leaves \(source.name) overdrawn."
        }
        return text
    }

    /// One end of the transfer. The account picked on the other side is left
    /// out, so the two can never be the same.
    /// - Parameters:
    ///   - label: Row title, "From" or "To".
    ///   - selection: The bound account id.
    ///   - excluding: The id chosen on the other side.
    /// - Returns: The configured picker.
    private func accountPicker(
        _ label: String,
        selection: Binding<UUID?>,
        excluding: UUID?
    ) -> some View {
        Picker(label, selection: selection) {
            Text("Choose an account").tag(UUID?.none)
            ForEach(accounts.filter { $0.id != excluding }) { account in
                Label(account.name, systemImage: account.symbolName)
                    .tag(Optional(account.id))
            }
        }
    }

    /// Preselects the two ends: the account it was opened from, or the first
    /// two in the list.
    private func load() {
        guard hasEnoughAccounts else { return }
        sourceID = initialSource?.id ?? accounts.first?.id
        destinationID = accounts.first { $0.id != sourceID }?.id
    }

    /// Writes the transfer and dismisses, surfacing the reason if it is refused.
    private func save() {
        guard let source, let destination else { return }
        do {
            try TransferService.transfer(
                from: source,
                to: destination,
                amount: amount,
                date: date,
                note: note,
                in: context
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
