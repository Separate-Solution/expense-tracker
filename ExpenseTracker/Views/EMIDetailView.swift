import SwiftUI
import SwiftData

/// One EMI in full: how far through it is, what it costs, every installment it
/// has posted or still owes, and the button that closes it early.
struct EMIDetailView: View {

    @Environment(\.modelContext) private var context

    let plan: EMIPlan

    @State private var isEditing = false
    @State private var isForeclosing = false
    @State private var isConfirmingReopen = false
    @State private var saveFailure: Error?

    private var paidCount: Int { plan.paidCount() }
    /// Read once for the whole instalment list rather than per row — the list
    /// runs to as many rows as the plan has payments.
    private var postedInstallments: [Transaction] { plan.installments }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(plan.status.title, systemImage: plan.status.symbolName)
                            .font(.caption)
                            .foregroundStyle(plan.status == .active ? .secondary : Theme.income)
                        Spacer()
                        Text("\(paidCount) of \(plan.installmentCount) paid")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    ProgressView(value: plan.progress())
                        .tint(Theme.income)
                    HStack {
                        Text(Formatters.currencyMagnitude(plan.amountPaid()) + " paid")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if plan.status.isRunning {
                            Text(Formatters.currencyMagnitude(plan.amountRemaining()) + " left")
                                .font(.caption)
                                .foregroundStyle(Theme.expense)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Terms") {
                LabeledContent("Instalment", value: Formatters.currencyMagnitude(plan.installmentAmount))
                LabeledContent("Schedule", value: "\(plan.cadenceSummary) · \(plan.installmentCount) payments")
                LabeledContent("Amount financed", value: Formatters.currencyMagnitude(plan.principal))
                LabeledContent("Interest rate", value: rateLabel)
                if let source = plan.sourceName {
                    LabeledContent(plan.creditCard == nil ? "Paid from" : "Charged to", value: source)
                }
                if let category = plan.category {
                    LabeledContent("Category", value: category.name)
                }
            }

            Section {
                LabeledContent("Total payable", value: Formatters.currencyMagnitude(plan.totalPayable))
                LabeledContent("Interest", value: Formatters.currencyMagnitude(plan.totalInterest))
                if plan.status.isRunning {
                    LabeledContent("Principal left", value: Formatters.currencyMagnitude(plan.outstandingPrincipal()))
                }
                LabeledContent("Started", value: plan.startDate.formatted(Formatters.shortDate))
                if let final = plan.finalInstallmentDate {
                    LabeledContent("Last instalment", value: final.formatted(Formatters.shortDate))
                }
                if let closed = plan.closedDate {
                    LabeledContent(plan.status == .foreclosed ? "Foreclosed" : "Completed",
                                   value: closed.formatted(Formatters.shortDate))
                }
            } header: {
                Text("Cost")
            } footer: {
                if plan.totalInterest > 0 {
                    Text("Interest is what the instalments add up to beyond the amount financed.")
                }
            }

            if plan.status.isRunning {
                Section {
                    Button {
                        isForeclosing = true
                    } label: {
                        Label("Foreclose this EMI", systemImage: "flag.checkered")
                    }
                } footer: {
                    Text(foreclosureFooter)
                }
            }

            if plan.status == .foreclosed {
                Section {
                    if let payment = plan.closingPayment {
                        LabeledContent("Settled with") {
                            AmountText(amount: payment.amount, type: .expense, font: .body)
                        }
                    }
                    Button("Reopen this EMI") { isConfirmingReopen = true }
                } footer: {
                    Text("Reopening removes the settlement payment and starts the remaining instalments again.")
                }
            }

            Section("Instalments") {
                let posted = postedInstallments
                ForEach(0..<plan.installmentCount, id: \.self) { index in
                    installmentRow(at: index, posted: posted)
                }
            }

            if !plan.note.isEmpty {
                Section("Note") {
                    Text(plan.note)
                }
            }
        }
        .navigationTitle(plan.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            EMIEditorView(plan: plan)
        }
        .sheet(isPresented: $isForeclosing) {
            EMIForeclosureSheet(plan: plan)
        }
        .confirmationDialog(
            "Reopen this EMI?",
            isPresented: $isConfirmingReopen,
            titleVisibility: .visible
        ) {
            Button("Reopen", role: .destructive) {
                EMIEngine.reopen(plan, in: context)
                if let failure = context.saveReportingFailure() {
                    saveFailure = failure
                } else {
                    EMIEngine.postDueInstallments(in: context)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The settlement payment is deleted and the instalments left resume from where they stopped.")
        }
        .saveFailureAlert($saveFailure)
    }

    /// The rate, or a plain label when there is nothing to charge.
    private var rateLabel: String {
        guard plan.annualInterestRate > 0 else { return "No cost" }
        return "\(Formatters.percent(plan.annualInterestRate)) a year"
    }

    /// What foreclosing would cost right now, spelled out before it is opened.
    private var foreclosureFooter: String {
        let principal = Formatters.currencyMagnitude(plan.outstandingPrincipal())
        let charge = plan.foreclosureCharge()
        guard charge > 0 else {
            return "Closing it today would settle roughly \(principal) of principal."
        }
        return "Closing it today would settle roughly \(principal) of principal, "
            + "plus \(Formatters.currencyMagnitude(charge)) in foreclosure charges "
            + "(\(Formatters.percent(plan.foreclosureChargePercent)))."
    }

    /// One scheduled instalment, marked with where it has got to.
    /// - Parameters:
    ///   - index: Zero-based instalment index.
    ///   - posted: The instalments that exist so far, oldest first.
    /// - Returns: The configured row.
    private func installmentRow(at index: Int, posted: [Transaction]) -> some View {
        let transaction = index < posted.count ? posted[index] : nil
        let date = transaction?.date ?? plan.installmentDate(at: index)

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Instalment \(index + 1)")
                    .font(.subheadline)
                if let date {
                    Text(date.formatted(Formatters.shortDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(status(of: transaction))
                .font(.caption)
                .foregroundStyle(transaction.map { plan.isSettled($0) } == true ? Theme.income : .secondary)
            Text(Formatters.currencyMagnitude(transaction?.amount ?? plan.installmentAmount))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(transaction == nil ? .secondary : .primary)
        }
    }

    /// Where one instalment stands: paid, sitting on a card bill that hasn't
    /// been cleared, or not yet due.
    /// - Parameter transaction: The posted instalment, or nil when it hasn't posted.
    /// - Returns: The short status label.
    private func status(of transaction: Transaction?) -> String {
        guard let transaction else { return "Scheduled" }
        if plan.isSettled(transaction) { return "Paid" }
        return plan.creditCard == nil ? "Due" : "On the card bill"
    }
}

/// Closing an EMI early. The plan quotes what it thinks settling costs — the
/// principal still owed plus the lender's charge — and the amount stays editable,
/// because the figure that matters is the one the lender actually asked for.
struct EMIForeclosureSheet: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let plan: EMIPlan

    @State private var amount: Decimal = .zero
    @State private var date = Date()
    @State private var isShowingAmountPad = false
    @State private var saveFailure: Error?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isShowingAmountPad = true
                    } label: {
                        HStack {
                            Text("Final payment").foregroundStyle(.primary)
                            Spacer()
                            AmountText(amount: amount, type: .expense, font: .title3)
                        }
                    }
                    DateTimeRow(selection: $date)
                } footer: {
                    Text(sourceFooter)
                }

                Section("What that covers") {
                    LabeledContent("Principal left",
                                   value: Formatters.currencyMagnitude(plan.outstandingPrincipal()))
                    LabeledContent("Foreclosure charge",
                                   value: Formatters.currencyMagnitude(plan.foreclosureCharge()))
                    LabeledContent("Suggested",
                                   value: Formatters.currencyMagnitude(plan.foreclosureQuote()))
                    LabeledContent("Instalments left",
                                   value: "\(plan.pendingCount()) of \(plan.installmentCount)")
                }
            }
            .navigationTitle("Foreclose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close EMI", action: foreclose).disabled(amount <= 0)
                }
            }
            .saveFailureAlert($saveFailure)
            .sheet(isPresented: $isShowingAmountPad) {
                AmountEntrySheet(amount: $amount, type: .expense)
            }
        }
        .onAppear { amount = plan.foreclosureQuote() }
    }

    /// Says where the settlement lands, which differs on a card.
    private var sourceFooter: String {
        guard let source = plan.sourceName else {
            return "Recorded as an expense, and the EMI is marked foreclosed."
        }
        return plan.creditCard == nil
            ? "Leaves \(source) and marks the EMI foreclosed. No further instalments post."
            : "Charged to \(source), so it lands on that card's next bill. No further instalments post."
    }

    /// Records the settlement and closes the plan.
    private func foreclose() {
        do {
            try EMIEngine.foreclose(plan, amount: amount, date: date, in: context)
        } catch {
            saveFailure = error
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
