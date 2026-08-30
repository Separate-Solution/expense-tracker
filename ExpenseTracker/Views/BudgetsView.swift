import SwiftUI
import SwiftData

/// The budgets list: what each one allows, what has gone against it so far, and
/// how much of the current period is left.
struct BudgetsView: View {

    @Environment(\.modelContext) private var context

    @Query(sort: \Budget.sortIndex) private var budgets: [Budget]
    @Query private var transactions: [Transaction]

    @State private var editingBudget: Budget?
    @State private var isCreating = false
    @State private var pendingDeletion: Budget?
    @State private var saveFailure: Error?

    private var activeBudgets: [Budget] { budgets.filter { !$0.isArchived } }
    private var archivedBudgets: [Budget] { budgets.filter(\.isArchived) }

    var body: some View {
        List {
            Section("Active") {
                if activeBudgets.isEmpty {
                    EmptyStateView(
                        symbol: "chart.pie",
                        title: "No budgets yet",
                        message: "Cap what a category costs you each month, or set a target to put aside."
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(activeBudgets) { budget in
                    budgetRow(budget)
                }
            }

            if !archivedBudgets.isEmpty {
                Section("Archived") {
                    ForEach(archivedBudgets) { budget in
                        budgetRow(budget)
                    }
                }
            }
        }
        .navigationTitle("Budgets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isCreating = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $isCreating) {
            BudgetEditorView(budget: nil)
        }
        .sheet(item: $editingBudget) { budget in
            BudgetEditorView(budget: budget)
        }
        .confirmationDialog(
            "Delete this budget?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete budget", role: .destructive) {
                if let pendingDeletion {
                    context.delete(pendingDeletion)
                    saveFailure = context.saveReportingFailure()
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("Your transactions are untouched — a budget only watches them.")
        }
        .saveFailureAlert($saveFailure)
    }

    /// One row of the budgets list, with its swipe actions.
    /// - Parameter budget: The budget to render.
    /// - Returns: The configured row view.
    private func budgetRow(_ budget: Budget) -> some View {
        Button {
            editingBudget = budget
        } label: {
            BudgetSummaryRow(
                budget: budget,
                progress: BudgetEngine.progress(for: budget, transactions: transactions)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDeletion = budget
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                budget.isArchived.toggle()
                saveFailure = context.saveReportingFailure()
            } label: {
                Label(budget.isArchived ? "Restore" : "Archive",
                      systemImage: budget.isArchived ? "tray.and.arrow.up" : "archivebox")
            }
            .tint(.orange)
        }
    }
}

/// Name, figures and progress bar for one budget's current period.
struct BudgetSummaryRow: View {

    let budget: Budget
    let progress: BudgetProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                CategoryBadge(symbolName: budget.kind.symbolName, colorHex: budget.colorHex)
                VStack(alignment: .leading, spacing: 2) {
                    Text(budget.name).foregroundStyle(.primary).lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatters.currencyMagnitude(progress.applied))
                        .font(.callout.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(amountTint)
                    Text("of \(Formatters.currencyMagnitude(progress.target))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            BudgetProgressBar(budget: budget, progress: progress)
        }
        .padding(.vertical, 2)
    }

    /// Cadence plus where the period stands — or why nothing is counting yet.
    private var subtitle: String {
        if budget.isArchived { return "\(budget.periodSummary) · archived" }
        if !progress.hasStarted {
            return "Starts \(Formatters.relativeDayLabel(for: budget.startDate))"
        }
        if progress.hasFinished { return "\(budget.periodSummary) · finished" }
        let days = progress.daysRemaining
        let dayLabel = days == 1 ? "1 day left" : "\(days) days left"
        return "\(budget.periodSummary) · \(dayLabel)"
    }

    /// Red only when an expense budget has been overspent; a savings target that
    /// has been met is good news, not a warning.
    private var amountTint: Color {
        guard progress.hasReachedTarget else { return .primary }
        return budget.kind == .expense ? Theme.expense : Theme.income
    }
}

/// The thin bar and caption under a budget row, matching the credit usage bar.
struct BudgetProgressBar: View {

    let budget: Budget
    let progress: BudgetProgress

    private var barColor: Color {
        if budget.kind == .expense && progress.hasReachedTarget { return Theme.expense }
        return Color(hex: budget.colorHex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(2, proxy.size.width * progress.fraction))
                }
            }
            .frame(height: 5)

            HStack {
                Text(leadingCaption)
                Spacer()
                Text(periodCaption)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    /// What is left, or how far past the target this period went.
    private var leadingCaption: String {
        if progress.overshoot > 0 {
            let word = budget.kind == .expense ? "over" : "past target"
            return "\(Formatters.currencyMagnitude(progress.overshoot)) \(word)"
        }
        return "\(Formatters.currencyMagnitude(progress.remaining)) \(budget.kind.remainingLabel)"
    }

    /// The window these figures cover, e.g. "1 Aug – 31 Aug".
    private var periodCaption: String {
        let start = progress.period.start.formatted(.dateTime.day().month(.abbreviated))
        let end = progress.period.lastMoment.formatted(.dateTime.day().month(.abbreviated))
        return "\(start) \u{2013} \(end)"
    }
}
