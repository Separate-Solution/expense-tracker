import SwiftUI
import SwiftData

struct RootView: View {

    enum Tab: Hashable {
        case home, transactions, accounts, settings
    }

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: Tab = .home
    @State private var isAddingTransaction = false

    /// Clears the tab bar so the floating button sits above it rather than on it.
    private let floatingButtonInset: CGFloat = 78

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(Tab.home)

                TransactionsView()
                    .tabItem { Label("Transactions", systemImage: "list.bullet") }
                    .tag(Tab.transactions)

                AccountsView()
                    .tabItem { Label("Accounts", systemImage: "creditcard") }
                    .tag(Tab.accounts)

                SettingsView()
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }

            if selectedTab == .home || selectedTab == .transactions {
                FloatingAddButton { isAddingTransaction = true }
                    .padding(.trailing, 20)
                    .padding(.bottom, floatingButtonInset)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: selectedTab)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: $isAddingTransaction) {
            AddTransactionFlow()
        }
        .task {
            SeedData.seedIfNeeded(in: context)
            RecurrenceEngine.postDueTransactions(in: context)
        }
        .onChange(of: scenePhase) { _, phase in
            // Catch up on subscriptions that fell due while the app was backgrounded.
            if phase == .active {
                RecurrenceEngine.postDueTransactions(in: context)
            }
        }
    }
}
