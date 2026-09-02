import SwiftUI
import SwiftData

/// Every EMI in one list: what is still running at the top, what has been paid
/// off underneath.
struct EMIsView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \EMIPlan.startDate, order: .reverse) private var plans: [EMIPlan]

    @State private var isCreating = false
    @State private var pendingDeletion: EMIPlan?
    @State private var saveFailure: Error?

    private var activePlans: [EMIPlan] { plans.filter { $0.status.isRunning } }
    private var closedPlans: [EMIPlan] { plans.filter { !$0.status.isRunning } }

    /// What every running plan still has to pay between them.
    private var totalRemaining: Decimal {
        activePlans.reduce(Decimal.zero) { $0 + $1.amountRemaining() }.roundedToCurrency
    }

    /// Roughly what the running plans cost each month, so cadences can be
    /// compared. Weeks use 4.345 (52 ÷ 12) and days use 30, the same
    /// approximation the recurring list uses.
    private var estimatedMonthlyOutgoing: Decimal {
        activePlans.reduce(Decimal.zero) { total, plan in
            let perPeriod = plan.installmentAmount / Decimal(max(1, plan.interval))
            switch plan.frequency {
            case .daily: return total + perPeriod * 30
            case .weekly: return total + perPeriod * Decimal(string: "4.345")!
            case .monthly: return total + perPeriod
            case .quarterly: return total + perPeriod / 3
            case .yearly: return total + perPeriod / 12
            }
        }
    }

    var body: some View {
        List {
            if !activePlans.isEmpty {
                Section {
                    LabeledContent("Left to pay") {
                        Text(Formatters.currencyMagnitude(totalRemaining))
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.expense)
                    }
                    LabeledContent("Roughly per month") {
                        Text(Formatters.currencyMagnitude(estimatedMonthlyOutgoing.roundedToCurrency))
                            .monospacedDigit()
                    }
                } footer: {
                    Text("Installments post themselves on the day they fall due. One charged to a card counts as paid when that card's bill is cleared.")
                }
            }

            Section("Running") {
                if activePlans.isEmpty {
                    EmptyStateView(
                        symbol: "calendar.badge.clock",
                        title: "No EMIs",
                        message: "Add a loan or an instalment purchase and each payment posts itself."
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(activePlans) { plan in
                    planRow(plan)
                }
            }

            if !closedPlans.isEmpty {
                Section("Closed") {
                    ForEach(closedPlans) { plan in
                        planRow(plan)
                    }
                }
            }
        }
        .navigationTitle("EMIs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isCreating = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $isCreating) {
            EMIEditorView(plan: nil)
        }
        // Lives on the List, not the row: a row-level dialog is torn down along
        // with the swipe state and never gets to present.
        .confirmationDialog(
            "Delete this EMI?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete EMI, keep history", role: .destructive) {
                if let pendingDeletion {
                    context.delete(pendingDeletion)
                    saveFailure = context.saveReportingFailure()
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("The installments it already posted stay in your history.")
        }
        .saveFailureAlert($saveFailure)
    }

    /// One row of the list, linking through to the plan's detail.
    /// - Parameter plan: The plan to render.
    /// - Returns: The configured row.
    private func planRow(_ plan: EMIPlan) -> some View {
        NavigationLink {
            EMIDetailView(plan: plan)
        } label: {
            HStack(spacing: 12) {
                CategoryBadge(
                    symbolName: plan.category?.symbol ?? "calendar.badge.clock",
                    colorHex: plan.category?.colorHex ?? Theme.paletteHexes[10]
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title).lineLimit(1)
                    Text(subtitle(for: plan))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if plan.status.isRunning {
                        ProgressView(value: plan.progress())
                            .tint(Theme.income)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    AmountText(amount: plan.installmentAmount, type: .expense, font: .callout)
                    Text("\(plan.paidCount()) of \(plan.installmentCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDeletion = plan
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Cadence plus where the plan has got to.
    /// - Parameter plan: The plan to describe.
    /// - Returns: E.g. "Every month · next 5 Mar 2026".
    private func subtitle(for plan: EMIPlan) -> String {
        guard plan.status.isRunning else {
            guard let closed = plan.closedDate else { return plan.status.title }
            return "\(plan.status.title) · \(closed.formatted(Formatters.shortDate))"
        }
        guard let next = plan.nextInstallmentDate() else {
            // Every installment has posted, but a card bill still has to be paid
            // before the plan can be called finished.
            return "\(plan.cadenceSummary) · awaiting the card bill"
        }
        return "\(plan.cadenceSummary) · next \(Formatters.relativeDayLabel(for: next))"
    }
}
