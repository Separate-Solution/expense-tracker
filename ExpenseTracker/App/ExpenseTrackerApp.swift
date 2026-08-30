import SwiftUI
import SwiftData

@main
struct ExpenseTrackerApp: App {

    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearanceMode.system.rawValue

    let container: ModelContainer

    /// Builds the SwiftData container for the six persisted models.
    /// A store that cannot be opened is treated as fatal at launch.
    init() {
        let schema = Schema([
            Account.self, CreditCard.self, Category.self, Transaction.self, RecurringRule.self,
            Budget.self
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // A store that cannot be opened is unrecoverable at launch; failing loudly
            // in development beats silently starting with no persistence.
            fatalError("Could not create the data store: \(error)")
        }
    }

    /// The stored appearance choice, defaulting to following the system.
    private var appearance: AppearanceMode {
        AppearanceMode(rawValue: appearanceRaw) ?? .system
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(appearance.colorScheme)
        }
        .modelContainer(container)
    }
}
