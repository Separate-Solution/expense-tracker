import SwiftUI

/// The rounded symbol tile used for categories everywhere in the app.
struct CategoryBadge: View {
    let symbolName: String
    let colorHex: String
    var size: CGFloat = 38

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Color(hex: colorHex).opacity(0.22))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(Color(hex: colorHex))
            )
    }
}

/// Small circular glyph for accounts.
struct AccountBadge: View {
    let symbolName: String
    let colorHex: String
    var size: CGFloat = 34

    var body: some View {
        Circle()
            .fill(Color(hex: colorHex).opacity(0.22))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(Color(hex: colorHex))
            )
    }
}
