import Foundation

/// Closet's search and filters: piece chips, colour swatches, the Suitcase filter and typed text
/// (LR-09, LR-11). Everything combines, and an empty filter matches everything.
public struct GarmentFilter: Hashable, Sendable {
    /// Piece chips. Empty means any kind.
    public var categories: Set<GarmentCategory>
    /// Colour swatches. A garment matches if any of its colours is selected. Empty means any.
    public var colors: Set<ColorName>
    public var packing: Packing
    /// Typed search. Matches name, brand, colour note and the names of suitcases it's in.
    public var query: String

    public init(
        categories: Set<GarmentCategory> = [],
        colors: Set<ColorName> = [],
        packing: Packing = .any,
        query: String = ""
    ) {
        self.categories = categories
        self.colors = colors
        self.packing = packing
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
        !categories.isEmpty || !colors.isEmpty || packing != .any || !trimmedQuery.isEmpty
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The matching garments, in the order given.
    public func apply(to garments: [Garment], suitcases: [Suitcase]) -> [Garment] {
        guard isActive else { return garments }
        let active = suitcases.filter { !$0.isArchived }
        var suitcaseNames: [Garment.ID: [String]] = [:]
        var packed: Set<Garment.ID> = []
        for suitcase in active {
            packed.formUnion(suitcase.garmentIDs)
            for id in suitcase.garmentIDs { suitcaseNames[id, default: []].append(suitcase.name) }
        }
        let members = packing.suitcaseID.flatMap { id in active.first { $0.id == id }?.garmentIDs } ?? []
        let text = trimmedQuery

        return garments.filter { garment in
            if !categories.isEmpty && !categories.contains(garment.category) { return false }
            if !colors.isEmpty && colors.isDisjoint(with: garment.colors) { return false }
            switch packing {
            case .any: break
            case .inASuitcase: if !packed.contains(garment.id) { return false }
            case .notPacked: if packed.contains(garment.id) { return false }
            case .suitcase: if !members.contains(garment.id) { return false }
            }
            guard !text.isEmpty else { return true }
            let fields =
                [garment.name, garment.brand ?? "", garment.colorNote ?? ""]
                + (suitcaseNames[garment.id] ?? [])
            return fields.contains { $0.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}

extension GarmentFilter.Packing {
    fileprivate var suitcaseID: Suitcase.ID? {
        if case .suitcase(let id) = self { id } else { nil }
    }
}
