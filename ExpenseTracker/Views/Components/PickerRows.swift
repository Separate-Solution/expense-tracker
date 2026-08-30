import SwiftUI

/// Horizontal swatch picker shared by the account and category editors.
struct ColorSwatchPicker: View {
    @Binding var selectedHex: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Theme.paletteHexes, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary, lineWidth: selectedHex == hex ? 2.5 : 0)
                                .padding(-3)
                        )
                        .onTapGesture { selectedHex = hex }
                        .accessibilityLabel("Colour \(hex)")
                }
            }
            .padding(.vertical, 6)
            // The selection ring is drawn 3pt outside the swatch with a 2.5pt
            // stroke, so it needs more room than the swatches themselves —
            // 2pt clipped the first one against the scroll view's edge.
            .padding(.horizontal, 6)
        }
    }
}

/// A grouped grid of SF Symbols to choose a category icon from.
struct CategoryIconPicker: View {
    @Binding var symbolName: String
    /// The category's colour, so the picker previews the badge as it will look.
    var colorHex: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(CategoryIcon.groups) { group in
                    Section {
                        ForEach(group.symbols, id: \.self) { symbol in
                            tile(for: symbol)
                        }
                    } header: {
                        Text(group.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 260)
    }

    /// One selectable symbol tile.
    /// - Parameter symbol: The SF Symbol name to render.
    /// - Returns: The configured tile view.
    private func tile(for symbol: String) -> some View {
        let isSelected = symbol == symbolName
        return Button {
            symbolName = symbol
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isSelected ? Color(hex: colorHex) : Color.secondary)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected
                              ? Color(hex: colorHex).opacity(0.22)
                              : Color(.tertiarySystemFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(hex: colorHex), lineWidth: isSelected ? 2 : 0)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
