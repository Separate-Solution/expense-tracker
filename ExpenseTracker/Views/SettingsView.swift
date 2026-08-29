import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var context

    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearanceMode.system.rawValue
    @AppStorage(SettingsKey.currencyCode) private var currencyCode = Locale.current.currency?.identifier ?? "USD"
    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID = ""

    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortIndex)
    private var accounts: [Account]
    @Query private var transactions: [Transaction]
    @Query private var categories: [Category]
    @Query private var rules: [RecurringRule]

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Organise") {
                    NavigationLink {
                        CategoriesView()
                    } label: {
                        Label("Categories", systemImage: "square.grid.2x2")
                            .badge(categories.count)
                    }

                    NavigationLink {
                        SubscriptionsView()
                    } label: {
                        Label("Recurring & Subscriptions", systemImage: "repeat")
                            .badge(rules.filter(\.isActive).count)
                    }
                }

                Section("Appearance") {
                    Picker(selection: $appearanceRaw) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    } label: {
                        Label("Theme", systemImage: "circle.lefthalf.filled")
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    NavigationLink {
                        CurrencyPickerView(selection: $currencyCode)
                    } label: {
                        HStack {
                            Label("Currency", systemImage: "coloncurrencysign.circle")
                            Spacer()
                            Text(currencyCode).foregroundStyle(.secondary)
                        }
                    }

                    Picker(selection: $defaultAccountID) {
                        Text("Most recently used").tag("")
                        ForEach(accounts) { account in
                            Text(account.name).tag(account.id.uuidString)
                        }
                    } label: {
                        Label("Default account", systemImage: "wallet.pass")
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Defaults")
                } footer: {
                    Text("Changing the currency only changes how amounts are displayed — stored values are untouched.")
                }

                Section("Data") {
                    NavigationLink {
                        DataManagementView()
                    } label: {
                        Label("Import, Export & Backup", systemImage: "arrow.up.arrow.down.circle")
                    }
                }

                Section {
                    LabeledContent("Transactions", value: "\(transactions.count)")
                    LabeledContent("Accounts", value: "\(accounts.count)")
                    LabeledContent("Version", value: appVersion)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct CurrencyPickerView: View {

    @Binding var selection: String
    @State private var searchText = ""

    private var codes: [String] {
        let all = Locale.commonISOCurrencyCodes
        guard !searchText.isEmpty else { return all }
        let needle = searchText.lowercased()
        return all.filter { code in
            code.lowercased().contains(needle)
                || (Locale.current.localizedString(forCurrencyCode: code)?.lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        List {
            ForEach(codes, id: \.self) { code in
                Button {
                    selection = code
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(code).foregroundStyle(.primary)
                            if let name = Locale.current.localizedString(forCurrencyCode: code) {
                                Text(name).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if selection == code {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
        // `.always` keeps the field pinned under the title instead of hiding it
        // until the list is pulled down.
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search currencies"
        )
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
    }
}
