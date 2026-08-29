import Foundation
import SwiftData

/// Turns recurring rules into real transactions. Runs on launch and on
/// foreground, and again whenever a rule is created or edited.
enum RecurrenceEngine {

    /// Creates any transaction that a rule says should already exist by `date`.
    /// Returns how many were created.
    @discardableResult
    static func postDueTransactions(in context: ModelContext, asOf date: Date = .now) -> Int {
        let descriptor = FetchDescriptor<RecurringRule>()
        guard let rules = try? context.fetch(descriptor) else { return 0 }

        var created = 0
        for rule in rules where rule.isActive {
            for index in rule.pendingIndexes(upTo: date) {
                guard let occurrence = rule.occurrenceDate(at: index) else { continue }
                let transaction = Transaction(
                    title: rule.title,
                    amount: rule.amount,
                    type: rule.type,
                    date: occurrence,
                    note: rule.note,
                    account: rule.account,
                    creditCard: rule.creditCard,
                    category: rule.category,
                    recurringRule: rule
                )
                context.insert(transaction)
                rule.lastPostedIndex = index
                created += 1
            }
        }

        if created > 0 {
            try? context.save()
        }
        return created
    }

    /// Marks every occurrence on or before `date` as already handled, so a rule
    /// created with a past start date does not backfill history.
    static func skipOccurrences(for rule: RecurringRule, upTo date: Date = .now) {
        let indexes = rule.pendingIndexes(upTo: date)
        if let last = indexes.last {
            rule.lastPostedIndex = last
        }
    }

    /// Rewrites future (not yet due) generated transactions after a rule is edited,
    /// leaving already-posted history untouched.
    static func applyEdits(of rule: RecurringRule, in context: ModelContext, asOf date: Date = .now) {
        let cutoff = date.endOfDay
        for transaction in rule.transactions ?? [] where transaction.date > cutoff {
            context.delete(transaction)
        }
    }
}
