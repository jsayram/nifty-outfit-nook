import Foundation

/// Saved Looks' search and filters (RD-08, LR-09): piece chips, colour swatches and typed search,
/// all combined. An empty filter matches every look.
///
/// Chips and swatches look at one piece at a time, so Bottoms with Black finds a look with black
/// bottoms ("No saved looks with black bottoms", LR-09), not any look with a bottom and something
/// black. With several chips or swatches on, any piece that is one of the kinds and one of the
/// colours will do. Ideas count as pieces too.
public struct LookFilter: Hashable, Sendable {
    /// Piece chips. Empty means any kind.
    public var categories: Set<GarmentCategory>
    /// Colour swatches. Empty means any colour.
    public var colors: Set<ColorName>
    /// Typed search. Every word must match the look's name, a piece's name, or one of the extra
    /// words the screen passes to `apply` (its names for the occasion, kinds and colours).
    public var query: String

    public init(categories: Set<GarmentCategory> = [], colors: Set<ColorName> = [], query: String = "") {
        self.categories = categories
        self.colors = colors
        self.query = query
    }

    /// True when any chip, swatch or text is set, so the screen shows Clear.
    public var isActive: Bool {
        hasChoices || !words.isEmpty
    }

    /// True when a chip or swatch is on, apart from typed text.
    public var hasChoices: Bool {
        !categories.isEmpty || !colors.isEmpty
    }

    /// The typed words, without extra spaces.
    public var words: [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// One piece of a look as the filter sees it: what it is, its colours and its name. A piece
    /// whose garment is gone for good has nothing to match and is left out.
    public struct Piece: Hashable, Sendable {
        public var category: GarmentCategory
        public var colors: [ColorName]
        public var name: String

        public init(category: GarmentCategory, colors: [ColorName], name: String) {
            self.category = category
            self.colors = colors
            self.name = name
        }

        public init(_ garment: Garment) {
            self.init(category: garment.category, colors: garment.colors, name: garment.name)
        }

        public init(_ idea: PieceIdea) {
            self.init(category: idea.category, colors: idea.colors, name: idea.name)
        }
    }

    /// The look's pieces, in piece order, from the garments she has (including ones she no longer
    /// owns or deleted, which are still in the look).
    public static func pieces(of look: Look, garments: [Garment.ID: Garment]) -> [Piece] {
        look.pieces.compactMap { piece in
            switch piece.content {
            case .garment(let id): garments[id].map(Piece.init)
            case .idea(let idea): Piece(idea)
            }
        }
    }

    /// True when the look matches every chip, swatch and word.
    ///
    /// - Parameters:
    ///   - pieces: the look's pieces (`pieces(of:garments:)`).
    ///   - extraWords: more words the look answers to, such as its occasion's name.
    ///   - pieceWords: more words a piece answers to, such as the names of its kind and colours.
    public func matches(
        name: String?,
        pieces: [Piece],
        extraWords: [String] = [],
        pieceWords: (Piece) -> [String] = { _ in [] }
    ) -> Bool {
        if hasChoices {
            let hasPiece = pieces.contains { piece in
                (categories.isEmpty || categories.contains(piece.category))
                    && (colors.isEmpty || !colors.isDisjoint(with: piece.colors))
            }
            if !hasPiece { return false }
        }
        let words = words
        guard !words.isEmpty else { return true }
        let fields = [name ?? ""] + extraWords + pieces.flatMap { [$0.name] + pieceWords($0) }
        return words.allSatisfy { word in
            fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    /// The matching looks, in the order given.
    public func apply(
        to looks: [Look],
        garments: [Garment.ID: Garment],
        extraWords: (Look) -> [String] = { _ in [] },
        pieceWords: (Piece) -> [String] = { _ in [] }
    ) -> [Look] {
        guard isActive else { return looks }
        return looks.filter { look in
            matches(
                name: look.name, pieces: Self.pieces(of: look, garments: garments), extraWords: extraWords(look),
                pieceWords: pieceWords)
        }
    }
}
