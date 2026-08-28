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
            .padding(.horizontal, 2)
        }
    }
}

/// A compact strip of emoji to choose a category glyph from.
struct EmojiPickerRow: View {
    @Binding var emoji: String

    private let suggestions = [
        "🛒", "🍔", "☕️", "🚕", "⛽️", "🛍️", "💡", "🏠", "💊", "🎬",
        "🔁", "✈️", "📚", "🧴", "🎁", "📦", "🐶", "👶", "🏋️", "🍿",
        "💼", "🧑‍💻", "🏢", "📈", "🏦", "↩️", "💰", "🪙", "🧾", "🎯"
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { option in
                    Text(option)
                        .font(.system(size: 22))
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(emoji == option
                                      ? Color.accentColor.opacity(0.25)
                                      : Color(.tertiarySystemFill))
                        )
                        .onTapGesture { emoji = option }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
