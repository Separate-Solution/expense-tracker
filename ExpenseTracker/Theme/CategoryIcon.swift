import Foundation

/// The SF Symbols catalogue that category badges draw from.
///
/// Categories used to carry a free-form emoji. They now carry an SF Symbol
/// name, which renders at a consistent weight and optical size and picks up
/// the category's colour. The mappings here exist so older data — stored
/// emoji, restored backups and third-party CSV exports — can be upgraded to a
/// sensible symbol instead of every category collapsing to a generic tag.
enum CategoryIcon {

    /// Used when nothing better can be inferred for an expense category.
    static let expenseFallback = "tag.fill"
    /// Used when nothing better can be inferred for an income category.
    static let incomeFallback = "banknote.fill"
    /// Stands in for a recurring rule whose category was deleted.
    static let recurringFallback = "arrow.triangle.2.circlepath"

    /// The fallback for a transaction with no category, so uncategorized
    /// income is not badged with the expense icon.
    /// - Parameter type: The transaction's type.
    /// - Returns: An SF Symbol name.
    static func fallback(for type: TransactionType) -> String {
        type == .expense ? expenseFallback : incomeFallback
    }

    /// One labelled block of the picker.
    struct Group: Identifiable {
        let title: String
        let symbols: [String]
        var id: String { title }
    }

    /// The full picker catalogue, in display order.
    static let groups: [Group] = [
        Group(title: "Everyday", symbols: [
            "cart.fill", "fork.knife", "cup.and.saucer.fill",
            "takeoutbag.and.cup.and.straw.fill", "wineglass.fill", "birthday.cake.fill",
            "bag.fill", "tshirt.fill", "carrot.fill", "basket.fill"
        ]),
        Group(title: "Home & bills", symbols: [
            "house.fill", "key.fill", "building.2.fill", "sofa.fill",
            "lightbulb.fill", "bolt.fill", "drop.fill", "flame.fill",
            "wifi", "phone.fill", "trash.fill", "wrench.and.screwdriver.fill"
        ]),
        Group(title: "Transport", symbols: [
            "car.fill", "fuelpump.fill", "bus.fill", "tram.fill",
            "airplane", "bicycle", "scooter", "parkingsign.circle.fill",
            "suitcase.fill", "figure.walk"
        ]),
        Group(title: "Health", symbols: [
            "cross.case.fill", "pills.fill", "stethoscope", "heart.fill",
            "dumbbell.fill", "figure.run", "leaf.fill", "checkmark.shield.fill"
        ]),
        Group(title: "Fun & learning", symbols: [
            "film.fill", "popcorn.fill", "gamecontroller.fill", "music.note",
            "headphones", "tv.fill", "ticket.fill", "sportscourt.fill",
            "book.fill", "graduationcap.fill", "camera.fill", "paintpalette.fill"
        ]),
        Group(title: "People", symbols: [
            "person.2.fill", "figure.and.child.holdinghands", "pawprint.fill",
            "gift.fill", "sparkles", "scissors", "hand.raised.fill", "envelope.fill"
        ]),
        Group(title: "Money & work", symbols: [
            "briefcase.fill", "laptopcomputer", "building.columns.fill", "creditcard.fill",
            "banknote.fill", "chart.line.uptrend.xyaxis", "chart.line.downtrend.xyaxis",
            "chart.pie.fill", "percent", "arrow.uturn.left.circle.fill",
            "arrow.left.arrow.right.circle.fill", "doc.text.fill"
        ]),
        Group(title: "Other", symbols: [
            "tag.fill", "shippingbox.fill", "target", "star.fill",
            "flag.fill", "bell.fill", "globe", "ellipsis.circle.fill"
        ])
    ]

    /// Every symbol in the catalogue, flattened.
    static var allSymbols: [String] { groups.flatMap(\.symbols) }

    /// True when `symbol` is one the picker can show as selected.
    /// - Parameter symbol: An SF Symbol name.
    /// - Returns: Whether the catalogue contains it.
    static func isKnown(_ symbol: String) -> Bool {
        allSymbols.contains(symbol)
    }

    // MARK: - Inference

    /// Best-effort symbol for a category, used for legacy rows, restored
    /// backups and imported files.
    /// - Parameters:
    ///   - name: The category name; matched against `nameKeywords`.
    ///   - emoji: A legacy glyph, if the row still has one.
    ///   - type: Chooses the fallback when nothing matches.
    /// - Returns: An SF Symbol name.
    static func inferred(name: String, emoji: String = "", type: TransactionType) -> String {
        if let fromEmoji = symbol(forEmoji: emoji) { return fromEmoji }
        if let fromName = symbol(forName: name) { return fromName }
        return fallback(for: type)
    }

    /// Maps a legacy glyph to its closest symbol.
    /// - Parameter emoji: The stored glyph; may be empty or carry a variation
    ///   selector.
    /// - Returns: A symbol name, or nil when the glyph is unknown.
    static func symbol(forEmoji emoji: String) -> String? {
        let trimmed = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return normalizedEmojiSymbols[normalize(trimmed)]
    }

    /// Matches a category name against known keywords.
    /// - Parameter name: The category name, in any case.
    /// - Returns: A symbol name, or nil when nothing matches.
    static func symbol(forName name: String) -> String? {
        let folded = name.lowercased()
        guard !folded.isEmpty else { return nil }
        return nameKeywords.first { folded.contains($0.keyword) }?.symbol
    }

    /// Maps an icon name used by another expense app's export.
    /// - Parameter iconName: The value of the file's icon column.
    /// - Returns: A symbol name, or nil when unrecognised.
    static func symbol(forImportedIconName iconName: String) -> String? {
        let key = iconName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return importedIconSymbols[key]
    }

    // MARK: - Tables

    /// Drops variation selectors so "✈️" and "✈" hit the same entry.
    private static func normalize(_ emoji: String) -> String {
        String(String.UnicodeScalarView(emoji.unicodeScalars.filter { $0 != "\u{FE0F}" }))
    }

    private static let normalizedEmojiSymbols: [String: String] = Dictionary(
        emojiSymbols.map { (normalize($0.key), $0.value) },
        uniquingKeysWith: { first, _ in first }
    )

    private static let emojiSymbols: [String: String] = [
        "🛒": "cart.fill", "🧺": "basket.fill", "🍎": "carrot.fill", "🥕": "carrot.fill",
        "🍔": "fork.knife", "🍕": "fork.knife", "🍽️": "fork.knife", "🥡": "takeoutbag.and.cup.and.straw.fill",
        "☕️": "cup.and.saucer.fill", "🍵": "cup.and.saucer.fill",
        "🍺": "wineglass.fill", "🍷": "wineglass.fill", "🎂": "birthday.cake.fill",
        "🛍️": "bag.fill", "👕": "tshirt.fill", "👗": "tshirt.fill",
        "🏠": "house.fill", "🏡": "house.fill", "🔑": "key.fill",
        "🏢": "building.2.fill", "🛋️": "sofa.fill",
        "💡": "lightbulb.fill", "⚡️": "bolt.fill", "💧": "drop.fill", "🔥": "flame.fill",
        "🌐": "wifi", "📶": "wifi", "📱": "phone.fill", "📞": "phone.fill",
        "🗑️": "trash.fill", "🛠️": "wrench.and.screwdriver.fill", "🔧": "wrench.and.screwdriver.fill",
        "🚕": "car.fill", "🚗": "car.fill", "⛽️": "fuelpump.fill",
        "🚌": "bus.fill", "🚆": "tram.fill", "🚇": "tram.fill", "🚝": "tram.fill",
        "✈️": "airplane", "🚲": "bicycle", "🛵": "scooter", "🅿️": "parkingsign.circle.fill",
        "🧳": "suitcase.fill", "🚶": "figure.walk",
        "🏥": "cross.case.fill", "💊": "pills.fill", "🩺": "stethoscope",
        "❤️": "heart.fill", "🏋️": "dumbbell.fill", "🏃": "figure.run",
        "🌿": "leaf.fill", "🛡️": "checkmark.shield.fill",
        "🎬": "film.fill", "🍿": "popcorn.fill", "🎮": "gamecontroller.fill",
        "🎵": "music.note", "🎧": "headphones", "📺": "tv.fill", "🎟️": "ticket.fill",
        "⚽️": "sportscourt.fill", "📚": "book.fill", "📖": "book.fill",
        "🎓": "graduationcap.fill", "📷": "camera.fill", "🎨": "paintpalette.fill",
        "🤝": "person.2.fill", "👥": "person.2.fill", "👶": "figure.and.child.holdinghands",
        "🐶": "pawprint.fill", "🐱": "pawprint.fill", "🐾": "pawprint.fill",
        "🎁": "gift.fill", "🧴": "sparkles", "✨": "sparkles", "✂️": "scissors", "💇": "scissors",
        "✉️": "envelope.fill",
        "💼": "briefcase.fill", "💻": "laptopcomputer", "🧑‍💻": "laptopcomputer",
        "🏦": "building.columns.fill", "💳": "creditcard.fill",
        "💰": "banknote.fill", "💵": "banknote.fill", "💴": "banknote.fill",
        "💶": "banknote.fill", "💷": "banknote.fill", "🪙": "banknote.fill",
        "📈": "chart.line.uptrend.xyaxis", "📉": "chart.line.downtrend.xyaxis",
        "📊": "chart.pie.fill", "🧾": "doc.text.fill", "📝": "doc.text.fill",
        "↩️": "arrow.uturn.left.circle.fill", "🔀": "arrow.left.arrow.right.circle.fill",
        "🔁": "arrow.triangle.2.circlepath", "🔄": "arrow.triangle.2.circlepath",
        "🏷️": "tag.fill", "📦": "shippingbox.fill", "🎯": "target",
        "⭐️": "star.fill", "🚩": "flag.fill", "🔔": "bell.fill", "🌍": "globe"
    ]

    /// Checked in order, so the more specific keywords come first.
    private static let nameKeywords: [(keyword: String, symbol: String)] = [
        ("grocer", "cart.fill"), ("supermarket", "cart.fill"), ("vegetable", "carrot.fill"),
        ("dining", "fork.knife"), ("restaurant", "fork.knife"), ("food", "fork.knife"),
        ("swiggy", "fork.knife"), ("zomato", "fork.knife"), ("takeaway", "takeoutbag.and.cup.and.straw.fill"),
        ("coffee", "cup.and.saucer.fill"), ("cafe", "cup.and.saucer.fill"), ("chai", "cup.and.saucer.fill"),
        ("alcohol", "wineglass.fill"), ("liquor", "wineglass.fill"),
        ("clothes", "tshirt.fill"), ("clothing", "tshirt.fill"), ("apparel", "tshirt.fill"),
        ("shopping", "bag.fill"), ("shop", "bag.fill"),
        ("rent", "house.fill"), ("home", "house.fill"), ("house", "house.fill"),
        ("furniture", "sofa.fill"), ("maintenance", "wrench.and.screwdriver.fill"), ("repair", "wrench.and.screwdriver.fill"),
        ("electric", "bolt.fill"), ("power", "bolt.fill"),
        ("water", "drop.fill"), ("gas", "flame.fill"),
        ("internet", "wifi"), ("wifi", "wifi"), ("broadband", "wifi"),
        ("mobile", "phone.fill"), ("phone", "phone.fill"), ("recharge", "phone.fill"),
        ("bill", "lightbulb.fill"), ("utilit", "lightbulb.fill"),
        ("fuel", "fuelpump.fill"), ("petrol", "fuelpump.fill"), ("diesel", "fuelpump.fill"),
        ("parking", "parkingsign.circle.fill"),
        ("bus", "bus.fill"), ("train", "tram.fill"), ("metro", "tram.fill"),
        ("flight", "airplane"), ("travel", "airplane"), ("trip", "suitcase.fill"), ("vacation", "suitcase.fill"),
        ("cycle", "bicycle"), ("bike", "scooter"),
        ("cab", "car.fill"), ("taxi", "car.fill"), ("uber", "car.fill"), ("ola", "car.fill"),
        ("transport", "car.fill"), ("commute", "car.fill"), ("car", "car.fill"),
        ("insur", "checkmark.shield.fill"),
        ("medic", "cross.case.fill"), ("pharma", "pills.fill"), ("doctor", "stethoscope"),
        ("hospital", "cross.case.fill"), ("health", "cross.case.fill"),
        ("gym", "dumbbell.fill"), ("fitness", "dumbbell.fill"), ("workout", "dumbbell.fill"),
        ("movie", "film.fill"), ("cinema", "film.fill"), ("entertain", "film.fill"),
        ("game", "gamecontroller.fill"), ("music", "music.note"), ("spotify", "music.note"),
        ("subscri", "arrow.triangle.2.circlepath"), ("membership", "arrow.triangle.2.circlepath"),
        ("educat", "graduationcap.fill"), ("school", "graduationcap.fill"), ("college", "graduationcap.fill"),
        ("tuition", "graduationcap.fill"), ("course", "book.fill"), ("book", "book.fill"),
        ("salon", "scissors"), ("haircut", "scissors"), ("grooming", "sparkles"),
        ("beauty", "sparkles"), ("personal care", "sparkles"),
        ("gift", "gift.fill"), ("donat", "gift.fill"), ("charity", "gift.fill"),
        ("pet", "pawprint.fill"), ("baby", "figure.and.child.holdinghands"),
        ("child", "figure.and.child.holdinghands"), ("kid", "figure.and.child.holdinghands"),
        ("salary", "briefcase.fill"), ("payroll", "briefcase.fill"), ("wage", "briefcase.fill"),
        ("freelance", "laptopcomputer"), ("consult", "laptopcomputer"),
        ("business", "building.2.fill"), ("office", "building.2.fill"),
        ("invest", "chart.line.uptrend.xyaxis"), ("stock", "chart.line.uptrend.xyaxis"),
        ("mutual", "chart.line.uptrend.xyaxis"), ("dividend", "chart.line.uptrend.xyaxis"),
        ("interest", "building.columns.fill"), ("bank", "building.columns.fill"),
        ("saving", "building.columns.fill"), ("deposit", "building.columns.fill"),
        ("loan", "building.columns.fill"), ("emi", "building.columns.fill"), ("mortgage", "building.columns.fill"),
        ("refund", "arrow.uturn.left.circle.fill"), ("reimburs", "arrow.uturn.left.circle.fill"),
        ("cashback", "arrow.uturn.left.circle.fill"),
        ("balance", "arrow.left.arrow.right.circle.fill"), ("transfer", "arrow.left.arrow.right.circle.fill"),
        ("correction", "arrow.left.arrow.right.circle.fill"), ("adjust", "arrow.left.arrow.right.circle.fill"),
        ("lent", "person.2.fill"), ("lend", "person.2.fill"), ("borrow", "person.2.fill"),
        ("owe", "person.2.fill"), ("debt", "person.2.fill"), ("split", "person.2.fill"),
        ("credit card", "creditcard.fill"), ("card", "creditcard.fill"),
        ("tax", "doc.text.fill"), ("fee", "doc.text.fill"), ("charge", "doc.text.fill"),
        ("cash", "banknote.fill"), ("goal", "target"),
        ("misc", "shippingbox.fill"), ("other", "shippingbox.fill")
    ]

    /// Icon names seen in other expense apps' CSV exports (Cashew and friends).
    private static let importedIconSymbols: [String: String] = [
        "groceries": "cart.fill", "cutlery": "fork.knife", "food": "fork.knife",
        "restaurant": "fork.knife", "coffee": "cup.and.saucer.fill",
        "tram": "tram.fill", "car": "car.fill", "fuel": "fuelpump.fill", "bus": "bus.fill",
        "bills": "lightbulb.fill", "home": "house.fill", "rent": "house.fill",
        "subscription": "arrow.triangle.2.circlepath",
        "coin": "banknote.fill", "money": "banknote.fill",
        "salary": "briefcase.fill", "work": "briefcase.fill",
        "loan": "building.columns.fill", "charts": "chart.pie.fill",
        "popcorn": "popcorn.fill", "movie": "film.fill",
        "shopping": "bag.fill", "gift": "gift.fill",
        "health": "cross.case.fill", "medical": "cross.case.fill",
        "travel": "airplane", "flight": "airplane",
        "education": "graduationcap.fill", "book": "book.fill",
        "phone": "phone.fill", "internet": "wifi",
        "pet": "pawprint.fill", "baby": "figure.and.child.holdinghands",
        "fitness": "dumbbell.fill", "beauty": "sparkles",
        "investment": "chart.line.uptrend.xyaxis", "bank": "building.columns.fill"
    ]
}
