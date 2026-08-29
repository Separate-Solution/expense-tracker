import SwiftUI
import SwiftData

/// Three-step entry: name → category → amount.
/// Each step fills the sheet on its own so the keypad gets the full width.
struct AddTransactionFlow: View {

    enum Step: Int, CaseIterable {
        case name, category, amount
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Category.sortIndex) private var allCategories: [Category]
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortIndex)
    private var accounts: [Account]

    @AppStorage(SettingsKey.defaultAccountID) private var defaultAccountID = ""

    @State private var step: Step = .name
    @State private var title = ""
    @State private var type: TransactionType = .expense
    @State private var selectedCategory: Category?
    @State private var selectedAccount: Account?
    @State private var date = Date()
    @State private var note = ""
    @State private var engine = CalculatorEngine()

    @State private var repeats = false
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var interval = 1
    @State private var hasEndDate = false
    @State private var endDate = Date().addingMonths(12)
    @State private var backfillPastOccurrences = true

    @State private var isShowingCategoryEditor = false
    @State private var isShowingDetails = false
    @State private var errorMessage: String?

    @FocusState private var isNameFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        guard let amount = engine.result else { return false }
        return amount.roundedToCurrency > 0 && !trimmedTitle.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .name: nameStep
                case .category: categoryStep
                case .amount: amountStep
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .name {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button {
                            goBack()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if step == .name {
                        Button("Next") { advanceFromName() }
                            .disabled(trimmedTitle.isEmpty)
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $isShowingCategoryEditor) {
                CategoryEditorView(category: nil, presetType: type) { created in
                    selectedCategory = created
                    step = .amount
                }
            }
            .sheet(isPresented: $isShowingDetails) {
                transactionDetailsSheet
            }
            .alert("Couldn't save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear(perform: setUpDefaults)
    }

    private var navigationTitle: String {
        switch step {
        case .name: return "New Transaction"
        case .category: return "Category"
        case .amount: return "Amount"
        }
    }

    // MARK: - Step 1: name

    private var nameStep: some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What was it for?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Coffee, rent, salary…", text: $title)
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .submitLabel(.next)
                    .focused($isNameFocused)
                    .onSubmit(advanceFromName)
                    .padding(.vertical, 6)

                Divider()
            }

            if !recentTitles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Tapping a recent name jumps straight to the amount with its
                    // last-used category already applied.
                    FlowLayout(spacing: 8) {
                        ForEach(recentTitles, id: \.self) { suggestion in
                            Button {
                                applySuggestion(suggestion)
                            } label: {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(Color(.secondarySystemFill)))
                                    .foregroundStyle(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .onAppear { isNameFocused = true }
    }

    /// Distinct titles from the ten most recent transactions.
    private var recentTitles: [String] {
        var descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 40
        let recent = (try? context.fetch(descriptor)) ?? []
        var seen = Set<String>()
        var result: [String] = []
        for transaction in recent {
            let key = transaction.title.lowercased()
            if seen.insert(key).inserted {
                result.append(transaction.title)
            }
            if result.count == 8 { break }
        }
        return result
    }

    /// Fills the form from a tapped recent name, copying the type, category
    /// and account from the most recent transaction with that title, then
    /// skipping straight to the amount when a category came with it.
    /// - Parameter suggestion: The chip the user tapped.
    private func applySuggestion(_ suggestion: String) {
        title = suggestion
        var descriptor = FetchDescriptor<Transaction>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 40
        if let match = ((try? context.fetch(descriptor)) ?? [])
            .first(where: { $0.title.lowercased() == suggestion.lowercased() }) {
            type = match.type
            selectedCategory = match.category
            if selectedAccount == nil { selectedAccount = match.account }
        }
        isNameFocused = false
        step = selectedCategory == nil ? .category : .amount
    }

    /// Moves from the name step to the category step, ignoring a blank name.
    private func advanceFromName() {
        guard !trimmedTitle.isEmpty else { return }
        isNameFocused = false
        step = .category
    }

    // MARK: - Step 2: category

    private var categoryStep: some View {
        VStack(spacing: 14) {
            Picker("Type", selection: $type) {
                ForEach(TransactionType.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .onChange(of: type) { _, _ in
                // The chosen category belongs to the other bucket now.
                if selectedCategory?.type != type { selectedCategory = nil }
            }

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                    ForEach(categories) { category in
                        categoryTile(category)
                    }
                    newCategoryTile
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }

            if categories.isEmpty {
                EmptyStateView(
                    symbol: "square.grid.2x2",
                    title: "No \(type.title.lowercased()) categories",
                    message: "Create one to carry on."
                )
            }
        }
        .padding(.top, 8)
    }

    private var categories: [Category] {
        allCategories.filter { $0.type == type && !$0.isArchived }
    }

    /// One tile in the category grid, showing selection state.
    /// - Parameter category: The category to render.
    /// - Returns: The configured tile view.
    private func categoryTile(_ category: Category) -> some View {
        Button {
            selectedCategory = category
            step = .amount
        } label: {
            VStack(spacing: 6) {
                CategoryBadge(emoji: category.emoji, colorHex: category.colorHex, size: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 52 * 0.3, style: .continuous)
                            .strokeBorder(Color.accentColor,
                                          lineWidth: selectedCategory?.id == category.id ? 2.5 : 0)
                    )
                Text(category.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 28, alignment: .top)
            }
        }
        .buttonStyle(.plain)
    }

    private var newCategoryTile: some View {
        Button {
            isShowingCategoryEditor = true
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 52 * 0.3, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "plus").foregroundStyle(.secondary))
                Text("New")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: 28, alignment: .top)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: amount

    private var amountStep: some View {
        VStack(spacing: 12) {
            summaryHeader
            optionChips
            Spacer(minLength: 0)
            CalculatorKeypad(
                engine: $engine,
                tint: type.tint,
                confirmLabel: "Save",
                confirmEnabled: canSave,
                onConfirm: save
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var summaryHeader: some View {
        HStack(spacing: 12) {
            Button {
                step = .category
            } label: {
                CategoryBadge(
                    emoji: selectedCategory?.emoji ?? "🏷️",
                    colorHex: selectedCategory?.colorHex ?? Theme.paletteHexes[8],
                    size: 42
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Button { step = .name } label: {
                    Text(trimmedTitle.isEmpty ? "Untitled" : trimmedTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                Text("\(type.title) · \(selectedCategory?.name ?? "Uncategorized")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var optionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(
                    systemImage: "calendar",
                    text: Formatters.relativeDayLabel(for: date),
                    isActive: !Calendar.current.isDateInToday(date)
                ) { isShowingDetails = true }

                chip(
                    systemImage: selectedAccount?.kind.symbolName ?? "wallet.pass",
                    text: selectedAccount?.name ?? "No account",
                    isActive: false
                ) { isShowingDetails = true }

                chip(
                    systemImage: "repeat",
                    text: repeats ? repeatSummary : "Once",
                    isActive: repeats
                ) { isShowingDetails = true }

                chip(
                    systemImage: "text.alignleft",
                    text: note.isEmpty ? "Note" : "Note added",
                    isActive: !note.isEmpty
                ) { isShowingDetails = true }
            }
            .padding(.vertical, 2)
        }
    }

    private var repeatSummary: String {
        interval == 1
            ? "Every \(frequency.unitLabel(interval: 1))"
            : "Every \(interval) \(frequency.unitLabel(interval: interval))"
    }

    /// A small tappable pill used for the date, account and note shortcuts.
    /// - Parameters:
    ///   - systemImage: Leading SF Symbol.
    ///   - text: Label text.
    ///   - isActive: Whether to draw the chip as set rather than empty.
    ///   - action: Run when tapped.
    /// - Returns: The configured chip view.
    private func chip(systemImage: String, text: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.caption)
                Text(text).font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(isActive ? Color.accentColor.opacity(0.2) : Color(.secondarySystemFill))
            )
            .foregroundStyle(isActive ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Details sheet

    private var transactionDetailsSheet: some View {
        NavigationStack {
            Form {
                Section("When") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    if date > Date.now.endOfDay {
                        Label("This will be logged as an upcoming transaction.",
                              systemImage: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Account") {
                    Picker("Account", selection: Binding(
                        get: { selectedAccount?.id },
                        set: { newValue in
                            selectedAccount = accounts.first { $0.id == newValue }
                        }
                    )) {
                        Text("None").tag(UUID?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                }

                Section("Repeat") {
                    Toggle("Repeats", isOn: $repeats.animation())
                    if repeats {
                        Picker("Frequency", selection: $frequency) {
                            ForEach(RecurrenceFrequency.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        Stepper("Every \(interval) \(frequency.unitLabel(interval: interval))",
                                value: $interval, in: 1...30)
                        Toggle("Has an end date", isOn: $hasEndDate.animation())
                        if hasEndDate {
                            DatePicker("Ends", selection: $endDate, in: date..., displayedComponents: .date)
                        }
                        if date < Date.now.startOfDay {
                            Toggle("Backfill past occurrences", isOn: $backfillPastOccurrences)
                        }
                    }
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShowingDetails = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Persistence

    /// Preselects the account: the one saved in Settings when it still exists,
    /// otherwise the first in the list. Leaves an existing choice alone.
    private func setUpDefaults() {
        guard selectedAccount == nil else { return }
        if let stored = UUID(uuidString: defaultAccountID),
           let match = accounts.first(where: { $0.id == stored }) {
            selectedAccount = match
        } else {
            selectedAccount = accounts.first
        }
    }

    /// Steps one screen back through name → category → amount, dismissing the
    /// whole flow from the first step.
    private func goBack() {
        switch step {
        case .name: dismiss()
        case .category: step = .name
        case .amount: step = .category
        }
    }

    /// Validates the entry, writes the transaction and dismisses.
    /// Refuses an unevaluable expression, a non-positive amount or a blank
    /// name, surfacing the reason in `errorMessage` instead of saving.
    private func save() {
        guard let rawAmount = engine.result else {
            errorMessage = "That calculation didn't work out — check for a division by zero."
            return
        }
        let amount = rawAmount.roundedToCurrency
        guard amount > 0 else {
            errorMessage = "Enter an amount greater than zero."
            return
        }
        guard !trimmedTitle.isEmpty else {
            errorMessage = "Give the transaction a name."
            return
        }

        if repeats {
            let rule = RecurringRule(
                title: trimmedTitle,
                amount: amount,
                type: type,
                frequency: frequency,
                interval: interval,
                startDate: date,
                endDate: hasEndDate ? endDate : nil,
                note: note,
                account: selectedAccount,
                category: selectedCategory
            )
            context.insert(rule)
            if !backfillPastOccurrences && date < Date.now.startOfDay {
                RecurrenceEngine.skipOccurrences(for: rule)
            }
            try? context.save()
            RecurrenceEngine.postDueTransactions(in: context)
        } else {
            let transaction = Transaction(
                title: trimmedTitle,
                amount: amount,
                type: type,
                date: date,
                note: note,
                account: selectedAccount,
                category: selectedCategory
            )
            context.insert(transaction)
            try? context.save()
        }

        if let account = selectedAccount {
            defaultAccountID = account.id.uuidString
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// Wrapping row layout for the "recent names" chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    /// Measures the wrapped rows at the proposed width.
    /// - Parameters:
    ///   - proposal: Size offered by the parent; an unset width means unbounded.
    ///   - subviews: The chips to lay out.
    ///   - cache: Unused.
    /// - Returns: The size needed for all rows.
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth, height: totalHeight)
    }

    /// Positions each chip left to right, wrapping to a new row at the edge.
    /// - Parameters:
    ///   - bounds: Rect to lay out within.
    ///   - proposal: Size offered by the parent.
    ///   - subviews: The chips to place.
    ///   - cache: Unused.
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
