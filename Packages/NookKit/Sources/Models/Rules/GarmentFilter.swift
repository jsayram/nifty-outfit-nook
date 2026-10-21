import Foundation

/// Closet's search and filters: piece chips, colour swatches, the Suitcase filter, the Dirty
/// chip and typed search (LR-09, LR-11, RD-11). Everything combines, and an empty filter
/// matches everything.
public struct GarmentFilter: Hashable, Sendable {
    /// Piece chips. Empty means any kind.
    public var categories: Set<GarmentCategory>
    /// Colour swatches. A garment matches if any of its colours is selected. Empty means any.
    public var colors: Set<ColorName>
    public var packing: Packing
    /// The Dirty chip, which only shows while laundry tracking is on (RD-11). `nil` means any.
    public var laundry: LaundryState?
    /// Typed search. Every word must match the name, one of its other names (Phase 21c), the
    /// brand, colour note or the name of a suitcase it's in, or one of the extra words the screen
    /// passes to `apply` (its kind, type and colours).
    public var query: String

    public init(
        categories: Set<GarmentCategory> = [],
        colors: Set<ColorName> = [],
        packing: Packing = .any,
        laundry: LaundryState? = nil,
        query: String = ""
    ) {
        self.categories = categories
        self.colors = colors
        self.packing = packing
        self.laundry = laundry
        self.query = query
    }

    /// The Suitcase filter (LR-11).
    public enum Packing: Hashable, Sendable {
        case any
        case inASuitcase
        case notPacked
        case suitcase(Suitcase.ID)
    }

    /// True when any filter or text is set, so the screen shows Clear.
    public var isActive: Bool {
        hasChoices || !words.isEmpty
    }

    /// True when a chip, swatch or the Suitcase filter is set, apart from typed text.
    public var hasChoices: Bool {
        !categories.isEmpty || !colors.isEmpty || packing != .any || laundry != nil
    }

    /// The typed words, without extra spaces.
    public var words: [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The matching garments, in the order given.
    ///
    /// - Parameter extraWords: More words a garment answers to, such as the screen's names for
    ///   its kind, type and colours ("Shoes", "Loafers", "Black"). Models has no display text, so the screen
    ///   supplies them.
    public func apply(
        to garments: [Garment],
        suitcases: [Suitcase],
        extraWords: (Garment) -> [String] = { _ in [] }
    ) -> [Garment] {
        guard isActive else { return garments }
        let context = Context(suitcases: suitcases, packing: packing)
        let words = words
        return garments.filter { garment in
            guard allowsChoices(garment, context) else { return false }
            guard !words.isEmpty else { return true }
            let fields = context.fields(of: garment, extraWords: extraWords(garment))
            return words.allSatisfy { Self.word($0, isIn: fields) }
        }
    }

    /// The most possible matches `possibleMatches` returns (PRD §7.6: a bounded section).
    public static let possibleMatchesMaximum = 8

    /// Pieces that have some of the typed words but not all of them, for the Possible matches
    /// section when `apply` finds nothing (PRD §7.6).
    ///
    /// The chips, swatches, Suitcase filter and Dirty chip still apply in full; only the typed
    /// words are loosened. Filler words ("my", "the") don't count either way, and with fewer than
    /// two other words there's nothing to loosen, so the answer is empty. Pieces with more of the
    /// words come first, then in the order given, and at most `possibleMatchesMaximum` come back.
    /// Nothing about the search is stored.
    ///
    /// - Parameter fillerWords: Words to leave out, compared ignoring case and accents. The screen
    ///   supplies them, since they depend on the language.
    public func possibleMatches(
        in garments: [Garment],
        suitcases: [Suitcase],
        fillerWords: Set<String> = [],
        extraWords: (Garment) -> [String] = { _ in [] }
    ) -> [PossibleMatch] {
        let words = contentWords(ignoring: fillerWords)
        guard words.count >= 2 else { return [] }
        let context = Context(suitcases: suitcases, packing: packing)
        let matches: [PossibleMatch] = garments.compactMap { garment in
            guard allowsChoices(garment, context) else { return nil }
            let fields = context.fields(of: garment, extraWords: extraWords(garment))
            let found = words.filter { Self.word($0, isIn: fields) }
            guard !found.isEmpty, found.count < words.count else { return nil }
            return PossibleMatch(
                garment: garment, matchedWords: found, missingWords: words.filter { !found.contains($0) })
        }
        // A stable sort: more words first, otherwise as given.
        let ranked = matches.enumerated().sorted { left, right in
            if left.element.matchedWords.count != right.element.matchedWords.count {
                return left.element.matchedWords.count > right.element.matchedWords.count
            }
            return left.offset < right.offset
        }
        return ranked.prefix(Self.possibleMatchesMaximum).map(\.element)
    }

    /// The typed words without filler words, each once, in the order typed.
    public func contentWords(ignoring fillerWords: Set<String>) -> [String] {
        let filler = Set(fillerWords.map(Self.key))
        var seen: Set<String> = []
        return words.filter { word in
            let key = Self.key(word)
            return !filler.contains(key) && seen.insert(key).inserted
        }
    }

    private static func key(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func word(_ word: String, isIn fields: [String]) -> Bool {
        fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// True when the chips, swatches, Dirty chip and Suitcase filter let the garment through.
    private func allowsChoices(_ garment: Garment, _ context: Context) -> Bool {
        if !categories.isEmpty && !categories.contains(garment.category) { return false }
        if !colors.isEmpty && colors.isDisjoint(with: garment.colors) { return false }
        if let laundry, garment.laundry != laundry { return false }
        switch packing {
        case .any: return true
        case .inASuitcase: return context.packed.contains(garment.id)
        case .notPacked: return !context.packed.contains(garment.id)
        case .suitcase: return context.members.contains(garment.id)
        }
    }

    /// The suitcases worked out once for a whole search.
    private struct Context {
        var suitcaseNames: [Garment.ID: [String]] = [:]
        var packed: Set<Garment.ID> = []
        var members: Set<Garment.ID> = []

        init(suitcases: [Suitcase], packing: Packing) {
            let active = suitcases.filter { !$0.isArchived }
            for suitcase in active {
                packed.formUnion(suitcase.garmentIDs)
                for id in suitcase.garmentIDs { suitcaseNames[id, default: []].append(suitcase.name) }
            }
            members = Set(packing.suitcaseID.flatMap { id in active.first { $0.id == id }?.garmentIDs } ?? [])
        }

        /// The text typed words are looked for in.
        func fields(of garment: Garment, extraWords: [String]) -> [String] {
            [garment.name, garment.brand ?? "", garment.colorNote ?? ""] + garment.otherNames
                + (suitcaseNames[garment.id] ?? []) + extraWords
        }
    }
}

/// A piece with some of the typed words but not all (PRD §7.6 possible matches): which words it
/// has, and which aren't recorded on it.
public struct PossibleMatch: Hashable, Sendable {
    public let garment: Garment
    /// The typed words it has, in the order typed.
    public let matchedWords: [String]
    /// The typed words it doesn't have, in the order typed.
    public let missingWords: [String]

    public init(garment: Garment, matchedWords: [String], missingWords: [String]) {
        self.garment = garment
        self.matchedWords = matchedWords
        self.missingWords = missingWords
    }
}

extension GarmentFilter.Packing {
    fileprivate var suitcaseID: Suitcase.ID? {
        if case .suitcase(let id) = self { id } else { nil }
    }
}
