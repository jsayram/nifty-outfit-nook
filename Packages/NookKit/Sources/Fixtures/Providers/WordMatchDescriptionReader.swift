import Foundation
import Models

/// "Describe in words" for Stage A (Phase 7b): a deterministic word matcher that runs on the
/// phone. It looks her words up in small lists (kinds of piece, colour and shade words, a few
/// words for cut, warmth, dressiness, seasons and occasions) and suggests the matching details.
/// It sends nothing anywhere and knows nothing about style: it only names what she already said.
///
/// "Sage green cardigan with gold buttons, soft and cozy" gives the name "Sage cardigan",
/// Layers, Green with the shade "Sage", Warm, and the detail "Gold buttons".
///
/// How it reads a description:
/// - The **first part** (up to the first comma, full stop, "with", "from", "by", "for", "that"
///   or "which") names the piece. The last
///   kind word there is the kind ("dress shoes" are shoes), and its colour words are the colours.
/// - Cut, warmth, dressiness, seasons and occasions come from anywhere in the text.
/// - "from Old Navy" or "by Uniqlo" (capitalised words) is the brand.
/// - What follows "with" up to the next comma is a detail for her notes.
public struct WordMatchDescriptionReader: GarmentDescriptionReader {
    public var latency: Duration

    public init(latency: Duration = .zero) {
        self.latency = latency
    }

    public func suggestions(for description: String) async throws(DescriptionError) -> [GarmentSuggestion] {
        if latency > .zero {
            do {
                try await Task.sleep(for: latency)
            } catch {
                throw .cancelled
            }
        }
        if Task.isCancelled { throw .cancelled }
        return Self.suggestions(for: description)
    }

    /// The suggestions for a description, in form order.
    public static func suggestions(for description: String) -> [GarmentSuggestion] {
        let tokens = tokenize(description)
        let firstPart = Array(tokens.prefix { !$0.isBoundary && !Vocabulary.partEnders.contains($0.folded) })
        let words = tokens.filter { !$0.isBoundary }

        var result: [GarmentSuggestion] = []
        let kind = firstPart.last { category(for: $0.folded) != nil }
        let colours = colourPhrases(in: firstPart)

        if let kind {
            let lead = colours.first.map { $0.nameWords + " " } ?? ""
            result.append(.name(capitalizedFirst(lead + kind.original.lowercased())))
            if let category = category(for: kind.folded) { result.append(.category(category)) }
        }
        if !colours.isEmpty {
            var families: [ColorName] = []
            for phrase in colours where !families.contains(phrase.family) { families.append(phrase.family) }
            result.append(.colors(families, note: colours.compactMap(\.note).first))
        }
        if let fit = firstMatch(in: words, Vocabulary.fits) { result.append(.fit(fit)) }
        if let dressiness = firstMatch(in: words, Vocabulary.dressiness) { result.append(.dressiness(dressiness)) }
        if let warmth = warmth(in: words) { result.append(.warmth(warmth)) }
        let seasons = Set(words.compactMap { Vocabulary.seasons[$0.folded] })
        if !seasons.isEmpty { result.append(.seasons(seasons)) }
        let occasions = Set(words.compactMap { Vocabulary.occasions[$0.folded] })
        if !occasions.isEmpty { result.append(.occasions(occasions)) }
        if let brand = brand(in: description) { result.append(.brand(brand)) }
        if let detail = detail(in: tokens) { result.append(.detail(detail)) }
        return result
    }

    // MARK: Words

    struct Token {
        var original: String
        /// Lower case, without accents.
        var folded: String
        var isBoundary: Bool
    }

    /// Words, and a boundary for each comma, full stop, semicolon, line break and the like.
    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        func flush() {
            guard !current.isEmpty else { return }
            let trimmed = current.trimmingCharacters(in: CharacterSet(charactersIn: "-'’"))
            if !trimmed.isEmpty {
                tokens.append(Token(original: trimmed, folded: fold(trimmed), isBoundary: false))
            }
            current = ""
        }
        for character in text {
            if character.isLetter || character == "-" || character == "'" || character == "’" {
                current.append(character)
            } else {
                flush()
                if ",.;:!?\n()".contains(character) {
                    tokens.append(Token(original: String(character), folded: "", isBoundary: true))
                }
            }
        }
        flush()
        return tokens
    }

    static func fold(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacing("’", with: "'")
    }

    /// The kind of piece a word names, trying the word as typed, then without or with a plural
    /// "s" ("blouses", "loafer").
    static func category(for word: String) -> GarmentCategory? {
        if let category = Vocabulary.categories[word] { return category }
        if word.hasSuffix("s"), let category = Vocabulary.categories[String(word.dropLast())] { return category }
        return Vocabulary.categories[word + "s"]
    }

    private static func firstMatch<Value>(in words: [Token], _ table: [String: Value]) -> Value? {
        words.lazy.compactMap { table[$0.folded] }.first
    }

    /// "Light" before a colour is a shade ("light pink"), not warmth.
    private static func warmth(in words: [Token]) -> Warmth? {
        for (index, word) in words.enumerated() {
            guard let warmth = Vocabulary.warmth[word.folded] else { continue }
            let next = words.indices.contains(index + 1) ? words[index + 1].folded : ""
            if Vocabulary.shadeModifiers.contains(word.folded) && Vocabulary.colours[next] != nil { continue }
            return warmth
        }
        return nil
    }

    // MARK: Colours

    struct ColourPhrase {
        var family: ColorName
        /// The words that lead the suggested name: "Sage", "Light pink", "Green".
        var nameWords: String
        /// Her word for the shade, when it's more than the family's name.
        var note: String?
    }

    /// The colours in the first part, in the order she said them. "Sage green" is one phrase
    /// (green, shade Sage), and so is "light pink" (pink, shade Light pink).
    static func colourPhrases(in words: [Token]) -> [ColourPhrase] {
        var phrases: [ColourPhrase] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            guard let colour = Vocabulary.colours[word.folded] else {
                index += 1
                continue
            }
            let previous = index > 0 ? words[index - 1] : nil
            let modifier = previous.flatMap { Vocabulary.shadeModifiers.contains($0.folded) ? $0 : nil }
            if colour.isShade {
                // "Sage green": the family word after a shade belongs to it.
                let next = words.indices.contains(index + 1) ? words[index + 1] : nil
                let skipsFamily = next.flatMap { Vocabulary.colours[$0.folded] }.map { !$0.isShade } ?? false
                let shade = [modifier?.original, word.original].compactMap { $0 }.joined(separator: " ").lowercased()
                phrases.append(ColourPhrase(family: colour.family, nameWords: shade, note: capitalizedFirst(shade)))
                index += skipsFamily ? 2 : 1
            } else if let modifier {
                let shade = (modifier.original + " " + word.original).lowercased()
                phrases.append(ColourPhrase(family: colour.family, nameWords: shade, note: capitalizedFirst(shade)))
                index += 1
            } else {
                phrases.append(ColourPhrase(family: colour.family, nameWords: word.original.lowercased(), note: nil))
                index += 1
            }
        }
        return phrases
    }

    // MARK: Brand and detail

    /// "from Old Navy" or "by Uniqlo": up to three capitalised words after "from" or "by".
    static func brand(in text: String) -> String? {
        let pattern = /\b(?:from|by) ((?:\p{Lu}[\p{L}\p{N}&'’.]*)(?: \p{Lu}[\p{L}\p{N}&'’.]*){0,2})/
        guard let match = text.firstMatch(of: pattern) else { return nil }
        let brand = String(match.output.1).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return brand.isEmpty ? nil : brand
    }

    /// What follows the first "with", up to the next comma or full stop: "with gold buttons" gives
    /// "Gold buttons".
    static func detail(in tokens: [Token]) -> String? {
        guard let start = tokens.firstIndex(where: { $0.folded == "with" }) else { return nil }
        let words = tokens[(start + 1)...].prefix { !$0.isBoundary }.map(\.original)
        guard !words.isEmpty else { return nil }
        let detail = words.prefix(8).joined(separator: " ").lowercased()
        return capitalizedFirst(detail)
    }

    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

/// The word lists. Plain vocabulary for naming what she described; no style or fit rules.
private enum Vocabulary {
    /// Words that end the part of a description that names the piece.
    static let partEnders: Set<String> = ["with", "from", "by", "for", "that", "which"]

    static let categories: [String: GarmentCategory] = {
        var table: [String: GarmentCategory] = [:]
        let lists: [(GarmentCategory, [String])] = [
            (
                .top,
                [
                    "top", "tee", "t-shirt", "tshirt", "shirt", "blouse", "sweater", "jumper", "hoodie", "sweatshirt",
                    "tank", "camisole", "cami", "polo", "turtleneck", "bodysuit", "tunic", "pullover", "crop-top",
                ]
            ),
            (
                .bottom,
                [
                    "jeans", "trousers", "pants", "skirt", "shorts", "leggings", "joggers", "chinos", "slacks",
                    "culottes", "sweatpants",
                ]
            ),
            (.dress, ["dress", "gown", "jumpsuit", "romper", "sundress"]),
            (
                .layer,
                [
                    "cardigan", "jacket", "blazer", "coat", "parka", "trench", "shacket", "kimono", "windbreaker",
                    "gilet",
                ]
            ),
            (
                .shoes,
                [
                    "shoe", "shoes", "heels", "flats", "sneakers", "trainers", "boots", "loafers", "sandals", "mules",
                    "pumps", "slippers", "wedges", "oxfords",
                ]
            ),
            (.bag, ["bag", "handbag", "purse", "tote", "clutch", "backpack", "crossbody"]),
            (
                .accessory,
                [
                    "scarf", "belt", "hat", "cap", "necklace", "earrings", "bracelet", "beanie", "gloves",
                    "sunglasses", "watch", "headband",
                ]
            ),
        ]
        for (category, words) in lists {
            for word in words { table[word] = category }
        }
        return table
    }()

    struct Colour {
        var family: ColorName
        var isShade: Bool
    }

    static let colours: [String: Colour] = {
        var table: [String: Colour] = [:]
        let families: [String: ColorName] = [
            "black": .black, "white": .white, "cream": .cream, "beige": .beige, "tan": .tan, "brown": .brown,
            "gray": .gray, "grey": .gray, "navy": .navy, "blue": .blue, "denim": .denim, "green": .green,
            "olive": .olive, "red": .red, "brick": .brick, "burgundy": .burgundy, "pink": .pink, "purple": .purple,
            "yellow": .yellow, "orange": .orange, "multicolor": .multicolor, "multicolour": .multicolor,
            "multicolored": .multicolor, "multicoloured": .multicolor,
        ]
        let shades: [String: ColorName] = [
            "ivory": .cream, "off-white": .cream, "creme": .cream, "camel": .tan, "khaki": .tan, "nude": .beige,
            "taupe": .beige,
            "chocolate": .brown, "espresso": .brown, "charcoal": .gray, "silver": .gray, "cobalt": .blue,
            "teal": .blue, "sage": .green, "mint": .green, "emerald": .green, "forest": .green, "rust": .brick,
            "terracotta": .brick, "maroon": .burgundy, "wine": .burgundy, "blush": .pink, "rose": .pink,
            "fuchsia": .pink, "coral": .orange, "lilac": .purple, "lavender": .purple, "plum": .purple,
            "mustard": .yellow,
        ]
        for (word, family) in families { table[word] = Colour(family: family, isShade: false) }
        for (word, family) in shades { table[word] = Colour(family: family, isShade: true) }
        return table
    }()

    /// Words that make a colour a shade: "light pink", "dusty rose".
    static let shadeModifiers: Set<String> = ["light", "dark", "pale", "deep", "bright", "dusty", "muted", "baby"]

    static let fits: [String: GarmentFit] = [
        "fitted": .fitted, "slim": .fitted, "skinny": .fitted, "tight": .fitted, "tailored": .fitted,
        "regular": .regular, "straight": .regular,
        "relaxed": .relaxed, "loose": .relaxed, "oversized": .relaxed, "baggy": .relaxed, "wide": .relaxed,
        "wide-leg": .relaxed, "flowy": .relaxed,
    ]

    static let warmth: [String: Warmth] = [
        "warm": .warm, "cozy": .warm, "cosy": .warm, "wool": .warm, "woolen": .warm, "woollen": .warm,
        "fleece": .warm, "thick": .warm, "chunky": .warm, "puffer": .warm, "knit": .warm, "knitted": .warm,
        "light": .light, "lightweight": .light, "linen": .light, "thin": .light, "sheer": .light, "airy": .light,
        "breezy": .light,
    ]

    static let dressiness: [String: Dressiness] = [
        "dressy": .dressy, "fancy": .dressy, "formal": .dressy, "elegant": .dressy, "silk": .dressy,
        "satin": .dressy, "velvet": .dressy, "sequin": .dressy, "sequined": .dressy, "sequinned": .dressy,
        "casual": .casual, "everyday": .casual, "lounge": .casual, "comfy": .casual, "sporty": .casual,
    ]

    static let seasons: [String: Season] = [
        "spring": .spring, "summer": .summer, "fall": .fall, "autumn": .fall, "winter": .winter,
    ]

    static let occasions: [String: Occasion] = [
        "office": .office, "work": .office, "date": .dateNight, "brunch": .brunch, "party": .event,
        "wedding": .event, "event": .event, "gala": .event, "concert": .concert, "gig": .concert,
        "festival": .concert,
    ]
}
