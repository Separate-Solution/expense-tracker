import SwiftUI

/// Shown after a CSV is picked and before anything is written. Every field the
/// importer reads is listed alongside the column it will read from, so a header
/// we didn't recognise appears as "Not imported" instead of vanishing quietly.
struct CSVColumnMappingView: View {

    let plan: CSVImportPlan
    let onImport: (CSVColumnMapping) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mapping: CSVColumnMapping
    /// Derived from whichever column Date currently points at, so pointing it
    /// somewhere new re-detects the format instead of reusing the first guess.
    @State private var dateFormats: [String]
    @State private var dateSample: String?

    /// Seeds the editable mapping, date formats and preview sample from the
    /// plan's automatic guess.
    /// - Parameters:
    ///   - plan: The parsed file awaiting import.
    ///   - onImport: Called with the confirmed mapping when the user imports.
    init(plan: CSVImportPlan, onImport: @escaping (CSVColumnMapping) -> Void) {
        self.plan = plan
        self.onImport = onImport
        let suggested = plan.suggestedMapping
        _mapping = State(initialValue: suggested)
        _dateFormats = State(initialValue: plan.dateFormats(inColumn: suggested.indices[.date]))
        _dateSample = State(initialValue: plan.values(inColumn: suggested.indices[.date]).first)
    }

    private var ignoredColumns: [String] { plan.ignoredColumns(for: mapping) }
    private var missingFields: [CSVField] { mapping.missingRequiredFields }

    var body: some View {
        NavigationStack {
            List {
                previewSection
                dateFormatSection
                columnsSection
                ignoredSection
            }
            .onChange(of: mapping.indices[.date]) { _, column in
                dateFormats = plan.dateFormats(inColumn: column)
                dateSample = plan.values(inColumn: column).first
                mapping.datePattern = dateFormats.first
            }
            .navigationTitle("Assign Columns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(mapping)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!missingFields.isEmpty)
                }
            }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(plan.headers.indices, id: \.self) { index in
                        columnPreview(index)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
        } header: {
            Text("\(plan.transactionCount) transaction\(plan.transactionCount == 1 ? "" : "s") in the file")
        } footer: {
            Text("Showing the first row. Check each column below reads what you expect.")
        }
    }

    /// One row of the column list: header, sample value and the fields
    /// currently reading it.
    /// - Parameter index: Column to render.
    /// - Returns: The configured row view.
    private func columnPreview(_ index: Int) -> some View {
        let value = plan.value(inFirstRow: index)
        let assigned = fields(readingColumn: index)
        return VStack(alignment: .leading, spacing: 3) {
            Text(headerLabel(index))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(value.isEmpty ? "—" : value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(assigned.isEmpty ? "Not imported" : assigned.map(\.label).joined(separator: ", "))
                .font(.caption2.weight(.medium))
                .foregroundStyle(assigned.isEmpty ? Theme.expense : Color.accentColor)
                .lineLimit(1)
        }
        .frame(width: 110, alignment: .leading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    // MARK: - Date format

    @ViewBuilder
    private var dateFormatSection: some View {
        if mapping.indices[.date] != nil {
            Section {
                if dateFormats.isEmpty {
                    Label(
                        "None of the formats we know match this column. Rows will be skipped unless you point Date at a different column.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(Theme.expense)
                } else {
                    Picker("Date Format", selection: $mapping.datePattern) {
                        ForEach(dateFormats, id: \.self) { pattern in
                            Text(pattern).tag(String?.some(pattern))
                        }
                    }
                    .pickerStyle(.menu)

                    if let sample = dateSample {
                        HStack {
                            Text(sample)
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(previewDate(sample))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.income)
                        }
                    }
                }
            } header: {
                Text("Date Format")
            } footer: {
                if dateFormats.count > 1 {
                    Text("\(dateFormats.count) formats fit every date in this file — day and month are ambiguous. Check the preview reads the way you meant.")
                        .foregroundStyle(Theme.expense)
                }
            }
        }
    }

    /// Shows how a sample date reads under the chosen pattern, so a wrong
    /// guess is visible before importing.
    /// - Parameter sample: A raw value from the date column.
    /// - Returns: The formatted date, or "Unreadable".
    private func previewDate(_ sample: String) -> String {
        guard let date = CSVService.parseDate(sample, using: mapping.datePattern) else {
            return "Unreadable"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Columns

    private var columnsSection: some View {
        Section {
            ForEach(CSVField.assignable) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Picker(selection: binding(for: field)) {
                        Text("Not imported").tag(Int?.none)
                        ForEach(plan.headers.indices, id: \.self) { index in
                            Text(headerLabel(index)).tag(Int?.some(index))
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(field.label)
                            if field.isRequired {
                                Text("Required")
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule().fill(Color(.tertiarySystemFill))
                                    )
                            }
                        }
                    }
                    .pickerStyle(.menu)

                    if mapping.indices[field] == nil {
                        Label(field.unassignedNote, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(field.isRequired ? Theme.expense : .secondary)
                    }
                }
                .padding(.vertical, 2)
                // Without this the separator starts after the info icon on rows
                // that show a note, leaving it short of the rows that don't.
                .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                    dimensions[.leading]
                }
            }
        } header: {
            Text("Columns")
        } footer: {
            if !missingFields.isEmpty {
                Text("Assign \(missingFields.map(\.label).joined(separator: " and ")) before importing.")
                    .foregroundStyle(Theme.expense)
            }
        }
    }

    // MARK: - Ignored

    @ViewBuilder
    private var ignoredSection: some View {
        if !ignoredColumns.isEmpty {
            Section {
                ForEach(ignoredColumns, id: \.self) { column in
                    Label(column, systemImage: "minus.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Not being imported")
            } footer: {
                Text("\(ignoredColumns.count) column\(ignoredColumns.count == 1 ? "" : "s") in the file "
                     + "\(ignoredColumns.count == 1 ? "isn't" : "aren't") mapped to anything. "
                     + "That's fine if you don't need \(ignoredColumns.count == 1 ? "it" : "them") — assign "
                     + "\(ignoredColumns.count == 1 ? "it" : "one") above if you do.")
            }
        }
    }

    // MARK: - Helpers

    /// A binding to the column assigned to `field`, for its picker.
    /// - Parameter field: The field being assigned.
    /// - Returns: A binding to its column index, nil when unassigned.
    private func binding(for field: CSVField) -> Binding<Int?> {
        Binding(
            get: { mapping.indices[field] },
            set: { mapping.indices[field] = $0 }
        )
    }

    /// The column's header, falling back to "Column N" when the file has none.
    /// - Parameter index: Column to name.
    /// - Returns: The display label.
    private func headerLabel(_ index: Int) -> String {
        let header = plan.headers[index]
        return header.isEmpty ? "Column \(index + 1)" : header
    }

    /// Fields currently mapped to a column — more than one is allowed, and
    /// none means the column is ignored.
    /// - Parameter index: Column to check.
    /// - Returns: The fields reading it.
    private func fields(readingColumn index: Int) -> [CSVField] {
        CSVField.assignable.filter { mapping.indices[$0] == index }
    }
}
