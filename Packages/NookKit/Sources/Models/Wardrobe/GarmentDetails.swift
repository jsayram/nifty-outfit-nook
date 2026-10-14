import Foundation

/// The facts about a piece she can type or pick when she adds or edits it: everything on the
/// Add a piece form, and nothing that changes for its own reason (ownership, laundry,
/// availability, wear and deletion stay on `Garment`).
///
/// Data tier: **Personal**, except `notes`, which is **Sensitive** (DATA_MAP.md). A draft holds
/// one of these, so a draft is Sensitive too.
public struct GarmentDetails: Hashable, Sendable, Codable {
    /// Her name for it. Required (`NameRules.garmentName`).
    public var name: String
    /// The kind of piece. Required, but `nil` until she picks one: a new piece never gets a kind
    /// she didn't choose or accept.
    public var category: GarmentCategory?
    /// Colour families, main colour first.
    public var colors: [ColorName]
    /// Her words for the shade. Empty means none.
    public var colorNote: String
    /// How it's cut. `nil` means she isn't sure.
    public var fit: GarmentFit?
    public var dressiness: Dressiness
    public var warmth: Warmth
    public var seasons: Set<Season>
    public var occasions: Set<Occasion>
    /// Empty means unknown.
    public var brand: String
    /// The size on the label, as written. Empty means unknown.
    public var sizeLabel: String
    /// **Sensitive** tier: never logged, never sent without a consented request.
    public var notes: String
    public var photo: PhotoReference

    public init(
        name: String = "",
        category: GarmentCategory? = nil,
        colors: [ColorName] = [],
        colorNote: String = "",
        fit: GarmentFit? = nil,
        dressiness: Dressiness = .smart,
        warmth: Warmth = .medium,
        seasons: Set<Season> = Set(Season.allCases),
        occasions: Set<Occasion> = [],
        brand: String = "",
        sizeLabel: String = "",
        notes: String = "",
        photo: PhotoReference = .noPhoto
    ) {
        self.name = name
        self.category = category
        self.colors = colors
        self.colorNote = colorNote
        self.fit = fit
        self.dressiness = dressiness
        self.warmth = warmth
        self.seasons = seasons
        self.occasions = occasions
        self.brand = brand
        self.sizeLabel = sizeLabel
        self.notes = notes
        self.photo = photo
    }

    /// A new piece before she has typed anything. The defaults match `Garment`'s: smart, medium
    /// warmth and every season, so a piece added with only a name and kind can still be styled.
    public static let blank = GarmentDetails()

    /// The details of an existing piece, for Edit.
    public init(_ garment: Garment) {
        self.init(
            name: garment.name,
            category: garment.category,
            colors: garment.colors,
            colorNote: garment.colorNote ?? "",
            fit: garment.fit,
            dressiness: garment.dressiness,
            warmth: garment.warmth,
            seasons: garment.seasons,
            occasions: garment.occasions,
            brand: garment.brand ?? "",
            sizeLabel: garment.sizeLabel ?? "",
            notes: garment.notes,
            photo: garment.photo
        )
    }

    /// Writes these details onto a garment, leaving its states (ownership, laundry, wear and so
    /// on) alone. Empty optional text becomes `nil`. Call it with checked details
    /// (`GarmentRules.checked`); a missing kind keeps the garment's own.
    public func apply(to garment: inout Garment) {
        garment.name = name
        if let category { garment.category = category }
        garment.colors = colors
        garment.colorNote = colorNote.isEmpty ? nil : colorNote
        garment.fit = fit
        garment.dressiness = dressiness
        garment.warmth = warmth
        garment.seasons = seasons
        garment.occasions = occasions
        garment.brand = brand.isEmpty ? nil : brand
        garment.sizeLabel = sizeLabel.isEmpty ? nil : sizeLabel
        garment.notes = notes
        garment.photo = photo
    }

    /// A new piece in her closet with these details: owned, clean and available.
    ///
    /// - Throws: the problems `GarmentRules` finds, so a piece with no name or kind is never made.
    public func makeGarment(id: Garment.ID, addedAt: Date) throws(GarmentProblems) -> Garment {
        let details = try GarmentRules.checked(self)
        guard let category = details.category else { throw GarmentProblems([.category: .missingChoice]) }
        var garment = Garment(id: id, name: details.name, category: category, addedAt: addedAt)
        details.apply(to: &garment)
        return garment
    }
}
