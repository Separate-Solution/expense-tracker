import SwiftUI
import SwiftData

struct CategoriesView: View {

    @Environment(\.modelContext) private var context
    @Query(sort: \Category.sortIndex) private var categories: [Category]

    @State private var type: TransactionType = .expense
    @State private var editingCategory: Category?
    @State private var isCreating = false
    @State private var pendingDeletion: Category?

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
                            CategoryBadge(emoji: category.emoji, colorHex: category.colorHex)
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
                            pendingDeletion = category
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
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let pendingDeletion {
                    context.delete(pendingDeletion)
                    try? context.save()
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("The transactions stay, but they become uncategorized. Hiding it instead keeps them labelled.")
        }
    }

    private var deletionPrompt: String {
        guard let pendingDeletion else { return "Delete category?" }
        let count = pendingDeletion.transactions?.count ?? 0
        return count == 0
            ? "Delete “\(pendingDeletion.name)”?"
            : "Delete “\(pendingDeletion.name)” used by \(count) transaction\(count == 1 ? "" : "s")?"
    }

    /// Edit mode deletes go through the same confirmation as the swipe action —
    /// the rows shown are `visible`, not the full `categories` query.
    private func confirmDeletion(at offsets: IndexSet) {
        guard let index = offsets.first else { return }
        pendingDeletion = visible[index]
    }

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
    @State private var emoji = "🏷️"
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
                        CategoryBadge(emoji: emoji, colorHex: colorHex, size: 52)
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
                    EmojiPickerRow(emoji: $emoji)
                    TextField("Or type any emoji", text: $emoji)
                        .font(.body)
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

    private func load() {
        guard let category else {
            type = presetType
            colorHex = Theme.paletteHexes[categories.count % Theme.paletteHexes.count]
            emoji = presetType == .expense ? "🏷️" : "💰"
            return
        }
        name = category.name
        emoji = category.emoji
        colorHex = category.colorHex
        type = category.type
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep a single visible glyph even if the field holds a longer string.
        let glyph = emoji.isEmpty ? "🏷️" : String(emoji.prefix(2))

        if let category {
            category.name = trimmed
            category.emoji = glyph
            category.colorHex = colorHex
            category.type = type
            try? context.save()
        } else {
            let created = Category(
                name: trimmed,
                emoji: glyph,
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
