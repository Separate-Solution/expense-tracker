import SwiftUI

/// One picker offering bank accounts and credit cards together, so choosing
/// what paid for something is a single decision rather than two.
struct PaymentSourcePicker: View {

    var label: String = "Paid with"
    let accounts: [Account]
    let cards: [CreditCard]
    /// Whether a transaction is allowed to have no source at all.
    var allowsNone: Bool = true
    @Binding var selection: PaymentSource?

    var body: some View {
        Picker(label, selection: $selection) {
            if allowsNone {
                Text("None").tag(PaymentSource?.none)
            }
            if !accounts.isEmpty {
                Section("Bank Accounts") {
                    ForEach(accounts) { account in
                        Label(account.name, systemImage: account.symbolName)
                            .tag(Optional(PaymentSource.account(account.id)))
                    }
                }
            }
            if !cards.isEmpty {
                Section("Credit Cards") {
                    ForEach(cards) { card in
                        Label(card.name, systemImage: card.symbolName)
                            .tag(Optional(PaymentSource.creditCard(card.id)))
                    }
                }
            }
        }
    }
}

/// Turns a `PaymentSource` back into the model it points at, and describes one
/// for rows and chips. Kept separate from the picker so the editors, the add
/// flow and the subscription sheet all resolve a selection the same way.
enum PaymentSourceResolver {

    /// The bank account a selection points at, if it is one.
    /// - Parameters:
    ///   - source: The selection to resolve.
    ///   - accounts: Accounts to look in.
    /// - Returns: The matching account, or nil.
    static func account(_ source: PaymentSource?, in accounts: [Account]) -> Account? {
        guard case .account(let id) = source else { return nil }
        return accounts.first { $0.id == id }
    }

    /// The credit card a selection points at, if it is one.
    /// - Parameters:
    ///   - source: The selection to resolve.
    ///   - cards: Cards to look in.
    /// - Returns: The matching card, or nil.
    static func card(_ source: PaymentSource?, in cards: [CreditCard]) -> CreditCard? {
        guard case .creditCard(let id) = source else { return nil }
        return cards.first { $0.id == id }
    }

    /// Display name for a selection, for chips and summary rows.
    /// - Parameters:
    ///   - source: The selection to describe.
    ///   - accounts: Accounts to look in.
    ///   - cards: Cards to look in.
    /// - Returns: The name, or nil when nothing is selected or found.
    static func name(
        _ source: PaymentSource?,
        accounts: [Account],
        cards: [CreditCard]
    ) -> String? {
        account(source, in: accounts)?.name ?? card(source, in: cards)?.name
    }

    /// SF Symbol for a selection, falling back to a neutral wallet glyph.
    /// - Parameters:
    ///   - source: The selection to describe.
    ///   - accounts: Accounts to look in.
    ///   - cards: Cards to look in.
    /// - Returns: The symbol name.
    static func symbolName(
        _ source: PaymentSource?,
        accounts: [Account],
        cards: [CreditCard]
    ) -> String {
        if let account = account(source, in: accounts) { return account.symbolName }
        if let card = card(source, in: cards) { return card.symbolName }
        return "wallet.pass"
    }

    /// The first sensible default: the stored preference when it still exists,
    /// otherwise the first bank account, otherwise the first card.
    /// - Parameters:
    ///   - storedID: The `SettingsKey.defaultAccountID` token.
    ///   - accounts: Accounts to look in.
    ///   - cards: Cards to look in.
    /// - Returns: The source to preselect, or nil when there is nothing to pick.
    static func preferred(
        storedID: String,
        accounts: [Account],
        cards: [CreditCard]
    ) -> PaymentSource? {
        if let stored = decode(storedID),
           name(stored, accounts: accounts, cards: cards) != nil {
            return stored
        }
        if let account = accounts.first { return .account(account.id) }
        if let card = cards.first { return .creditCard(card.id) }
        return nil
    }

    /// Encodes a selection for `@AppStorage`.
    /// - Parameter source: The selection to store.
    /// - Returns: A token that `decode` reads back.
    static func encode(_ source: PaymentSource?) -> String {
        switch source {
        case .account(let id): return "account:\(id.uuidString)"
        case .creditCard(let id): return "card:\(id.uuidString)"
        case nil: return ""
        }
    }

    /// Reads a stored token. A bare UUID is accepted so the preference saved
    /// before credit cards existed still resolves to its account.
    /// - Parameter token: The stored string.
    /// - Returns: The decoded selection, or nil.
    static func decode(_ token: String) -> PaymentSource? {
        if let id = UUID(uuidString: token) { return .account(id) }
        let parts = token.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
        switch parts[0] {
        case "account": return .account(id)
        case "card": return .creditCard(id)
        default: return nil
        }
    }
}
