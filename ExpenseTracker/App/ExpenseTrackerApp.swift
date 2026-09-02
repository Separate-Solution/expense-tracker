import SwiftUI
import SwiftData

@main
struct ExpenseTrackerApp: App {

    @AppStorage(SettingsKey.appearance) private var appearanceRaw = AppearanceMode.system.rawValue

    let container: ModelContainer

    /// Builds the SwiftData container for the seven persisted models.
    /// A store that cannot be opened is treated as fatal at launch.
    ///
    /// A model added here also has to reach `BackupService.wipeSteps`, or it
    /// will survive erasing all data and restoring a backup.
    init() {
        let schema = Schema([
            Account.self, CreditCard.self, Category.self, Transaction.self, RecurringRule.self,
            Budget.self, EMIPlan.self
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
