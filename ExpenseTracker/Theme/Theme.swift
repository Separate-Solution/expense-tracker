import SwiftUI

/// Minimal palette. Everything structural comes from system materials so light/dark
/// mode work for free; only accents and category colours are hand-picked.
enum Theme {

    // MARK: - Semantic colours

    static let expense = Color(hex: "E5534B")
    static let income = Color(hex: "3FB950")

    /// Colour choices offered when creating accounts and categories.
    static let paletteHexes: [String] = [
        "6B7FE3", "E5534B", "3FB950", "E3A008", "A371F7",
        "3FB6C8", "F778BA", "F0883E", "8B949E", "56D364",
        "58A6FF", "DB6D28"
    ]

    // MARK: - Layout constants

    static let cornerRadius: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let rowSpacing: CGFloat = 10
}

extension Color {
    /// Accepts "RRGGBB" or "#RRGGBB". Falls back to grey on anything unparseable.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .gray
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Card container used across the app — one place to change the whole look.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

extension View {
    func cardBackground() -> some View { modifier(CardBackground()) }
}

/// The three appearance options exposed in Settings.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
