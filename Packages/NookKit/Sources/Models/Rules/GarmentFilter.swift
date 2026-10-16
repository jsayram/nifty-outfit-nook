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
    /// Typed search. Every word must match the name, brand, colour note or the name of a
    /// suitcase it's in, or one of the extra words the screen passes to `apply`.
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
    ///   its kind and colours ("Shoes", "Black"). Models has no display text, so the screen
    ///   supplies them.
    public func apply(
        to garments: [Garment],
        suitcases: [Suitcase],
        extraWords: (Garment) -> [String] = { _ in [] }
    ) -> [Garment] {
        guard isActive else { return garments }
        let active = suitcases.filter { !$0.isArchived }
        var suitcaseNames: [Garment.ID: [String]] = [:]
        var packed: Set<Garment.ID> = []
        for suitcase in active {
            packed.formUnion(suitcase.garmentIDs)
            for id in suitcase.garmentIDs { suitcaseNames[id, default: []].append(suitcase.name) }
        }
        let members = packing.suitcaseID.flatMap { id in active.first { $0.id == id }?.garmentIDs } ?? []
        let words = words

        return garments.filter { garment in
            if !categories.isEmpty && !categories.contains(garment.category) { return false }
            if !colors.isEmpty && colors.isDisjoint(with: garment.colors) { return false }
            if let laundry, garment.laundry != laundry { return false }
            switch packing {
            case .any: break
            case .inASuitcase: if !packed.contains(garment.id) { return false }
            case .notPacked: if packed.contains(garment.id) { return false }
            case .suitcase: if !members.contains(garment.id) { return false }
            }
            guard !words.isEmpty else { return true }
            let fields =
                [garment.name, garment.brand ?? "", garment.colorNote ?? ""]
                + (suitcaseNames[garment.id] ?? []) + extraWords(garment)
            return words.allSatisfy { word in
                fields.contains { $0.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
        }
    }
}

extension GarmentFilter.Packing {
    fileprivate var suitcaseID: Suitcase.ID? {
        if case .suitcase(let id) = self { id } else { nil }
    }
}
