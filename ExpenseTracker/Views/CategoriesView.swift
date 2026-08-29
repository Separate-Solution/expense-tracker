import SwiftUI
import SwiftData

struct CategoriesView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var type: TransactionType = .expense
    @State private var editingCategory: Category?
    @State private var isCreating = false
    @State private var pendingDeletion: [Category] = []

    private var visible: [Category] {
        categories.filter { $0.type == type }
    }

    var body: some View {
        List {
            Section {
                Picker("Type", selection: $type) {
                    ForEach(TransactionType.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            Section {
                if visible.isEmpty {
                    EmptyStateView(
                        symbol: "square.grid.2x2",
                        title: "No categories",
                        message: "Add one to start sorting your \(type.title.lowercased())s."
                    )
                    .listRowBackground(Color.clear)
                }
                ForEach(visible) { category in
                    Button {
                        editingCategory = category
                    } label: {
                        HStack(spacing: 12) {
                            CategoryBadge(symbolName: category.symbol, colorHex: category.colorHex)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name).foregroundStyle(.primary)
                                Text("\(category.transactions?.count ?? 0) transactions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if category.isArchived {
                                Text("Hidden")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = [category]
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            category.isArchived.toggle()
                            try? context.save()
                        } label: {
                            Label(category.isArchived ? "Show" : "Hide",
                                  systemImage: category.isArchived ? "eye" : "eye.slash")
                        }
                        .tint(.orange)
                    }
                }
                .onMove(perform: move)
                .onDelete(perform: confirmDeletion)
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isCreating = true } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .topBarLeading) { EditButton() }
        }
        .sheet(isPresented: $isCreating) {
            CategoryEditorView(category: nil, presetType: type)
        }
        .sheet(item: $editingCategory) { category in
            CategoryEditorView(category: category, presetType: category.type)
        }
        // Lives on the List, not the row: a row-level dialog is torn down along
        // with the swipe state and never gets to present.
        .confirmationDialog(
            deletionPrompt,
            isPresented: Binding(
                get: { !pendingDeletion.isEmpty },
                set: { if !$0 { pendingDeletion = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                for category in pendingDeletion {
                    context.delete(category)
                }
                try? context.save()
                pendingDeletion = []
            }
            Button("Cancel", role: .cancel) { pendingDeletion = [] }
        } message: {
            Text("The transactions stay, but they become uncategorized. Hiding it instead keeps them labelled.")
        }
    }

    private var deletionPrompt: String {
        guard let first = pendingDeletion.first else { return "Delete category?" }
        let uses = pendingDeletion.reduce(0) { $0 + ($1.transactions?.count ?? 0) }
        let subject = pendingDeletion.count == 1
            ? "“\(first.name)”"
            : "\(pendingDeletion.count) categories"
        return uses == 0
            ? "Delete \(subject)?"
            : "Delete \(subject) used by \(uses) transaction\(uses == 1 ? "" : "s")?"
    }

    /// Edit mode deletes go through the same confirmation as the swipe action —
    /// the rows shown are `visible`, not the full `categories` query, and a
    /// single gesture can select more than one row.
    private func confirmDeletion(at offsets: IndexSet) {
        pendingDeletion = offsets.map { visible[$0] }
    }

    /// Reorders categories and renumbers `sortIndex` across the visible list.
    /// - Parameters:
    ///   - source: Rows being moved.
    ///   - destination: Index they are dropped before.
    private func move(from source: IndexSet, to destination: Int) {
        var reordered = visible
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, category) in reordered.enumerated() {
            category.sortIndex = index
        }
        try? context.save()
    }
}

struct CategoryEditorView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil means "create a new category".
    let category: Category?
    let presetType: TransactionType
    /// Called with the newly created category, so the add flow can select it.
    var onCreate: ((Category) -> Void)?

    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var name = ""
    @State private var symbolName = CategoryIcon.expenseFallback
    @State private var colorHex = Theme.paletteHexes[0]
    @State private var type: TransactionType = .expense

    private var isNew: Bool { category == nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        CategoryBadge(symbolName: symbolName, colorHex: colorHex, size: 52)
                        TextField("Name", text: $name)
                            .font(.title3)
                    }
                }

                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(TransactionType.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Icon") {
                    CategoryIconPicker(symbolName: $symbolName, colorHex: colorHex)
                }

                Section("Colour") {
                    ColorSwatchPicker(selectedHex: $colorHex)
                }
            }
            .navigationTitle(isNew ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
        .onAppear(perform: load)
    }

    /// Fills the form from the category being edited, or picks sensible
    /// defaults (next palette colour, type-appropriate icon) for a new one.
    private func load() {
        guard let category else {
            type = presetType
            colorHex = Theme.paletteHexes[categories.count % Theme.paletteHexes.count]
            symbolName = CategoryIcon.fallback(for: presetType)
            return
        }
        name = category.name
        symbolName = category.symbol
        colorHex = category.colorHex
        type = category.type
    }

    /// Creates or updates the category and dismisses.
    /// A new category is appended after the last one of its type.
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let category {
            category.name = trimmed
            category.symbolName = symbolName
            category.colorHex = colorHex
            category.type = type
            try? context.save()
        } else {
            let created = Category(
                name: trimmed,
                symbol: symbolName,
                colorHex: colorHex,
                type: type,
                sortIndex: (categories.filter { $0.type == type }.map(\.sortIndex).max() ?? -1) + 1
            )
            context.insert(created)
            try? context.save()
            onCreate?(created)
        }
        dismiss()
    }
}
