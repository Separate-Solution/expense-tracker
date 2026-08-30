import SwiftUI

/// The dashboard's budgets block: where each budget stands in the period it is
/// currently in. Tapping one opens it for editing, the same as from the list.
struct BudgetsDashboardSection: View {

    let budgets: [Budget]
    /// Every transaction, so each budget can pick out the ones it counts.
    let transactions: [Transaction]

    @State private var editingBudget: Budget?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Budgets")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                NavigationLink {
                    BudgetsView()
                } label: {
                    Text("All").font(.caption)
                }
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(budgets.enumerated()), id: \.element.id) { index, budget in
                    Button {
                        editingBudget = budget
                    } label: {
                        BudgetSummaryRow(
                            budget: budget,
                            progress: BudgetEngine.progress(for: budget, transactions: transactions)
                        )
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < budgets.count - 1 { Divider() }
                }
            }
            .cardBackground()
        }
        .sheet(item: $editingBudget) { budget in
            BudgetEditorView(budget: budget)
        }
    }
}
