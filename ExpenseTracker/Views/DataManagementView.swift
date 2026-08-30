import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataManagementView: View {

    @Environment(\.modelContext) private var context

    @Query private var transactions: [Transaction]

    /// Only one file importer may be attached to a single view — stacking two
    /// means only the last one works, so both are driven by this enum.
    enum ImportKind: Identifiable {
        case csv, backup
        var id: Self { self }

        var contentTypes: [UTType] {
            switch self {
            case .csv: return [.commaSeparatedText, .plainText, .text]
            case .backup: return [.json]
            }
        }
    }

    @State private var exportedFile: ExportedFile?
    @State private var importKind: ImportKind?
    @State private var isConfirmingErase = false
    @State private var isConfirmingRestore = false
    @State private var pendingRestore: BackupPayload?
    @State private var pendingCSV: CSVImportPlan?
    /// Set by the mapping sheet's Import button; the import itself runs in
    /// `onDismiss` so the result alert isn't presented while the sheet closes.
    /// It carries its own copy of the plan because `sheet(item:)` clears
    /// `pendingCSV` before `onDismiss` runs.
    @State private var confirmedImport: ConfirmedImport?
    /// Non-nil while a long data task runs; drives the determinate overlay.
    @State private var progress: TaskProgress?

    struct ConfirmedImport {
        let plan: CSVImportPlan
        let mapping: CSVColumnMapping
    }

    @State private var statusTitle = ""
    @State private var statusMessage = ""
    @State private var isShowingStatus = false

    var body: some View {
        List {
            Section {
                Button {
                    exportCSV()
                } label: {
                    Label("Export transactions as CSV", systemImage: "tablecells")
                }
                .disabled(transactions.isEmpty)

                Button {
                    importKind = .csv
                } label: {
                    Label("Import from CSV", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("CSV")
            } footer: {
                Text("Columns: Date, Time, Title, Type, Amount, Currency, Account, Account Type, Credit Card, Category, Note, ID. "
                     + "Importing any other file works too — you'll get to check which column feeds which field before anything is saved. "
                     + "Accounts, credit cards and categories in the file are created if they don't exist, and rows whose ID already exists are skipped. "
                     + "A row naming both an account and a credit card is read as a bill payment.")
            }

            Section {
                Button {
                    exportBackup()
                } label: {
                    Label("Create backup file", systemImage: "arrow.down.doc")
                }

                Button {
                    importKind = .backup
                } label: {
                    Label("Restore from backup", systemImage: "arrow.up.doc")
                }
                // Attached to the row itself so the dialog points at the button
                // it belongs to rather than at the middle of the list.
                .confirmationDialog(
                    "Replace all data with this backup?",
                    isPresented: $isConfirmingRestore,
                    titleVisibility: .visible
                ) {
                    Button("Restore and replace", role: .destructive) { performRestore() }
                    Button("Cancel", role: .cancel) { pendingRestore = nil }
                } message: {
                    if let pendingRestore {
                        Text("The backup holds \(pendingRestore.transactions.count) transactions across \(pendingRestore.accounts.count) accounts, made on \(pendingRestore.exportedAt.formatted(Formatters.shortDate)). Everything currently in the app will be removed.")
                    }
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("A backup contains everything — accounts, credit cards, categories, recurring rules and transactions. Restoring replaces all current data.")
            }

            Section {
                Button(role: .destructive) {
                    isConfirmingErase = true
                } label: {
                    Label("Erase all data", systemImage: "trash")
                }
                .confirmationDialog(
                    "Erase everything?",
                    isPresented: $isConfirmingErase,
                    titleVisibility: .visible
                ) {
                    Button("Erase all data", role: .destructive) { eraseAll() }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("This can't be undone. Make a backup first if you're not sure.")
                }
            } footer: {
                Text("Removes every account, credit card, category, rule and transaction, then restores the default categories.")
            }
        }
        .navigationTitle("Data")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if let progress {
                TaskProgressOverlay(progress: progress)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: progress == nil)
        .sheet(item: $exportedFile) { file in
            ShareSheet(url: file.url)
        }
        .sheet(item: $pendingCSV, onDismiss: runConfirmedImport) { plan in
            CSVColumnMappingView(plan: plan) { mapping in
                confirmedImport = ConfirmedImport(plan: plan, mapping: mapping)
            }
        }
        .fileImporter(
            isPresented: Binding(
                get: { importKind != nil },
                set: { if !$0 { importKind = nil } }
            ),
            allowedContentTypes: importKind?.contentTypes ?? [.json],
            allowsMultipleSelection: false
        ) { result in
            switch importKind {
            case .backup: handleBackupSelection(result)
            default: handleCSVImport(result)
            }
            importKind = nil
        }
        .alert(statusTitle, isPresented: $isShowingStatus) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(statusMessage)
        }
    }

    // MARK: - Export

    /// Writes every transaction to a timestamped CSV and opens the share sheet.
    private func exportCSV() {
        run("Writing CSV") { report in
            let csv = await CSVService.exportString(transactions: transactions, onProgress: report)
            let name = ExportFileWriter.timestampedName(prefix: "expenses", extension: "csv")
            exportedFile = try ExportFileWriter.write(csv, named: name)
        } onFailure: { error in
            showStatus("Export failed", error.localizedDescription)
        }
    }

    /// Writes a full JSON backup to a timestamped file and opens the share sheet.
    private func exportBackup() {
        run("Writing backup") { report in
            // Two whole-file steps rather than a per-row count that would be
            // invented: the snapshot, then encoding it.
            let payload = try BackupService.makePayload(from: context)
            report(0.5)
            await Task.yield()
            let data = try BackupService.encode(payload)
            let name = ExportFileWriter.timestampedName(prefix: "expense-tracker-backup", extension: "json")
            exportedFile = try ExportFileWriter.write(data, named: name)
            report(1)
        } onFailure: { error in
            showStatus("Backup failed", error.localizedDescription)
        }
    }

    // MARK: - Import

    /// Parses the chosen CSV into a plan and opens the mapping screen.
    /// Nothing is written until the user confirms the mapping.
    /// - Parameter result: Outcome of the file importer.
    private func handleCSVImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            showStatus("Import failed", error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            progress = TaskProgress(label: "Reading file")
            defer { progress = nil }
            do {
                let text = try readSecurityScoped(url) { try String(contentsOf: $0, encoding: .utf8) }
                confirmedImport = nil
                pendingCSV = try CSVService.prepare(from: text)
            } catch {
                showStatus("Import failed", error.localizedDescription)
            }
        }
    }

    /// Runs once the mapping sheet has closed, and only if it closed via Import.
    private func runConfirmedImport() {
        guard let confirmed = confirmedImport else { return }
        confirmedImport = nil
        run("Importing transactions") { report in
            let defaultAccount = try context.fetch(FetchDescriptor<Account>())
                .filter { !$0.isArchived }
                .sorted { $0.sortIndex < $1.sortIndex }
                .first
            let summary = try await CSVService.commit(
                confirmed.plan,
                mapping: confirmed.mapping,
                into: context,
                defaultAccount: defaultAccount,
                onProgress: report
            )
            showStatus("Import finished", describe(summary))
        } onFailure: { error in
            showStatus("Import failed", error.localizedDescription)
        }
    }

    /// Turns an import summary into the alert body: counts, anything created,
    /// and the first few skipped rows with a tally of the rest.
    /// - Parameter summary: The result of the import.
    /// - Returns: The message to show.
    private func describe(_ summary: CSVImportSummary) -> String {
        var lines = ["Imported \(summary.imported) transaction\(summary.imported == 1 ? "" : "s")."]
        if summary.skippedDuplicates > 0 {
            lines.append("Skipped \(summary.skippedDuplicates) already in the app.")
        }
        if !summary.createdAccounts.isEmpty {
            let unique = Array(Set(summary.createdAccounts)).sorted()
            lines.append("Created accounts: \(unique.joined(separator: ", ")).")
        }
        if !summary.createdCreditCards.isEmpty {
            let unique = Array(Set(summary.createdCreditCards)).sorted()
            lines.append("Created credit cards: \(unique.joined(separator: ", ")). Set their limits in Accounts.")
        }
        if !summary.createdCategories.isEmpty {
            let unique = Array(Set(summary.createdCategories)).sorted()
            lines.append("Created categories: \(unique.joined(separator: ", ")).")
        }
        if !summary.ignoredColumns.isEmpty {
            lines.append("Columns not imported: \(summary.ignoredColumns.joined(separator: ", ")).")
        }
        if !summary.failures.isEmpty {
            lines.append("")
            lines.append("\(summary.failures.count) row\(summary.failures.count == 1 ? "" : "s") skipped:")
            lines.append(contentsOf: summary.failures.prefix(5))
            if summary.failures.count > 5 {
                lines.append("…and \(summary.failures.count - 5) more.")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Decodes the chosen backup and asks for confirmation. Restoring is
    /// destructive, so nothing is applied until the dialog is accepted.
    /// - Parameter result: Outcome of the file importer.
    private func handleBackupSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            showStatus("Couldn't open backup", error.localizedDescription)
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let data = try readSecurityScoped(url) { try Data(contentsOf: $0) }
                pendingRestore = try BackupService.decode(data)
                isConfirmingRestore = true
            } catch {
                showStatus("Couldn't open backup", error.localizedDescription)
            }
        }
    }

    /// Replaces all current data with the confirmed backup and reports what
    /// came back.
    private func performRestore() {
        guard let payload = pendingRestore else { return }
        pendingRestore = nil
        run("Restoring backup") { report in
            let summary = try await BackupService.restore(
                payload,
                into: context,
                onProgress: report
            )
            showStatus(
                "Restored",
                "\(summary.transactions) transactions, \(summary.accounts) accounts, "
                + "\(summary.creditCards) credit cards, \(summary.categories) categories "
                + "and \(summary.recurringRules) recurring rules are back."
            )
        } onFailure: { error in
            showStatus("Restore failed", error.localizedDescription)
        }
    }

    /// Deletes everything and reseeds the default categories.
    private func eraseAll() {
        run("Erasing everything") { report in
            try await BackupService.eraseAll(in: context, reseed: true, onProgress: report)
            showStatus("Erased", "Everything is gone and the default categories are back.")
        } onFailure: { error in
            showStatus("Couldn't erase", error.localizedDescription)
        }
    }

    /// Runs one long data task behind the determinate overlay.
    ///
    /// The work stays on the main actor — SwiftData's context can't leave it —
    /// so the overlay only moves because the task yields between chunks. The
    /// label is set before the first chunk so the sheet never shows an empty
    /// ring.
    /// - Parameters:
    ///   - label: What to show under the ring.
    ///   - work: The task, handed a closure to report its progress with.
    ///   - onFailure: Shown if the task throws.
    private func run(
        _ label: String,
        work: @escaping (@escaping (Double) -> Void) async throws -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        progress = TaskProgress(label: label)
        Task {
            defer { progress = nil }
            do {
                try await work { fraction in
                    progress?.advance(to: fraction)
                }
            } catch {
                onFailure(error)
            }
        }
    }

    /// Files picked from Files/iCloud need their sandbox access opened first.
    private func readSecurityScoped<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    /// Presents the shared result alert.
    /// - Parameters:
    ///   - title: Alert title.
    ///   - message: Alert body.
    private func showStatus(_ title: String, _ message: String) {
        statusTitle = title
        statusMessage = message
        isShowingStatus = true
    }
}

/// UIActivityViewController wrapper — plain ShareLink can't present a file URL
/// from inside a List row reliably on all iOS versions.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    /// Creates the share sheet for the staged file.
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    /// No-op: the share sheet is configured once at creation.
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
