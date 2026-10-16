import Foundation

/// Her profile: the name on the sign, her preferences and her optional fit details.
///
/// Each field's data tier is noted on it (SECURITY_STANDARD.md §1, DATA_MAP.md). Everything in
/// `measurements`, `fitPieces` and `tryOnPhoto` is **Sensitive**: it stays on the device, is
/// never logged, and leaves only inside a consented request, as the minimum needed.
public struct Profile: Hashable, Sendable, Codable {
    /// First name on the wooden sign (RD-03). **Personal**; never put in a prompt.
    /// Empty is allowed: the sign then shows a neutral fallback (RD-03.2).
    public var signName: String
    /// **Personal.**
    public var preferences: Preferences
    /// Her usual fit, "Saved until you change it" (LR-18). `nil` until she sets it.
    /// **Personal** on its own; **Sensitive** when sent with body details.
    public var usualFit: Comfort?
    /// Colours she likes to wear. **Personal.**
    public var likedColors: [ColorName]
    /// Colours she'd rather not wear. **Personal.**
    public var avoidedColors: [ColorName]
    /// Optional body measurements. **Sensitive.**
    public var measurements: BodyMeasurements
    /// The units Fit and measurements shows: inches and pounds, or centimetres and kilograms.
    /// `nil` until she picks, which means the region's usual units
    /// (`MeasurementUnits.preferred(for:)`). **Personal.**
    public var units: MeasurementUnits?
    /// "Add a piece that fits you well" (LR-13). **Sensitive.**
    public var fitPieces: [FitPiece]
    /// "Your try-on photo" (RD-06). **Sensitive**: a photo of her.
    public var tryOnPhoto: PhotoReference?
    /// What Style Me starts from next time: the source and occasion she chose last (FR-67,
    /// Phase 13). **Personal**: a suitcase can say where she'll be.
    public var remembered: RememberedChoices

    public init(
        signName: String = "",
        preferences: Preferences = Preferences(),
        usualFit: Comfort? = nil,
        likedColors: [ColorName] = [],
        avoidedColors: [ColorName] = [],
        measurements: BodyMeasurements = BodyMeasurements(),
        units: MeasurementUnits? = nil,
        fitPieces: [FitPiece] = [],
        tryOnPhoto: PhotoReference? = nil,
        remembered: RememberedChoices = RememberedChoices()
    ) {
        self.signName = signName
        self.preferences = preferences
        self.usualFit = usualFit
        self.likedColors = likedColors
        self.avoidedColors = avoidedColors
        self.measurements = measurements
        self.units = units
        self.fitPieces = fitPieces
        self.tryOnPhoto = tryOnPhoto
        self.remembered = remembered
    }
}

/// The choices Style Me remembers between requests (FR-67, PRD §7.7).
///
/// The source is the one she chose last, in Suitcases, on a suitcase, or on Style Me; Home's
/// suitcase shows it. The occasion is the one she picked last on Style Me, and Home's calendar
/// shows it. Comfort, colour and weather are never remembered: they're for one request only
/// (RD-02.4). Her words for Other aren't kept either, so choosing Other leaves the remembered
/// occasion as it was.
///
/// Data tier: **Personal**.
public struct RememberedChoices: Hashable, Sendable, Codable {
    public var source: WardrobeSource
    public var occasion: Occasion

    public init(source: WardrobeSource = .mainCloset, occasion: Occasion = .office) {
        self.source = source
        self.occasion = occasion
    }
}

/// Her standing choices. A fresh install gets the defaults below (LR-03, LR-10, RD-11).
///
/// Data tier: **Personal**.
public struct Preferences: Hashable, Sendable, Codable {
    /// "Preferences" on Style Me (LR-03). Default: Mine + one idea.
    public var pieceMode: PieceMode
    /// "Avoid repeating outfits for" (LR-10). Default: 1 week.
    public var repeatWindow: RepeatWindow
    /// "Track laundry" (RD-11). Off by default.
    public var tracksLaundry: Bool

    public init(
        pieceMode: PieceMode = .mineAndOneIdea,
        repeatWindow: RepeatWindow = .oneWeek,
        tracksLaundry: Bool = false
    ) {
        self.pieceMode = pieceMode
        self.repeatWindow = repeatWindow
        self.tracksLaundry = tracksLaundry
    }
}

/// Whether Something new may add one piece she doesn't own (LR-03, LR-05b).
public enum PieceMode: String, CaseIterable, Hashable, Sendable, Codable {
    /// Closet first, with one new-piece idea in Something new. Lily's default.
    case mineAndOneIdea
    /// Only pieces she owns, in every version.
    case onlyMine
}

/// "Avoid repeating outfits for" (LR-10).
public enum RepeatWindow: String, CaseIterable, Hashable, Sendable, Codable {
    case oneWeek
    case twoWeeks
    /// "I don't mind": nothing is skipped for wear.
    case noLimit

    /// The window in days, or `nil` when nothing is skipped.
    public var days: Int? {
        switch self {
        case .oneWeek: 7
        case .twoWeeks: 14
        case .noLimit: nil
        }
    }
}

/// A clothing comfort choice. The same three words describe her usual fit (Profile, saved until
/// she changes it) and today's Comfort on Style Me (this request only). LR-18 keeps them apart.
///
/// Data tier: **Sensitive** when it's today's comfort (health-adjacent, DATA_MAP.md); only these
/// neutral clothing words are stored, never symptoms or free text.
public enum Comfort: String, CaseIterable, Hashable, Sendable, Codable {
    case fitted
    case comfortable
    case relaxed

    /// The garment cut that matches this comfort, for plain stored-fact matching.
    public var matchingFit: GarmentFit {
        switch self {
        case .fitted: .fitted
        case .comfortable: .regular
        case .relaxed: .relaxed
        }
    }
}

/// Optional body measurements (PRD §10.1). Every value can be left out or cleared.
///
/// Data tier: **Sensitive**. Kept on the device; only the minimum relevant fact goes out, inside
/// a consented request (DATA_MAP.md). Weight is kept apart from the lengths and never decides a
/// size on its own (PRD §10).
public struct BodyMeasurements: Hashable, Sendable, Codable {
    public var height: Length?
    public var waist: Length?
    public var bust: Length?
    public var hips: Length?
    public var inseam: Length?
    public var weight: Weight?

    public init(
        height: Length? = nil,
        waist: Length? = nil,
        bust: Length? = nil,
        hips: Length? = nil,
        inseam: Length? = nil,
        weight: Weight? = nil
    ) {
        self.height = height
        self.waist = waist
        self.bust = bust
        self.hips = hips
        self.inseam = inseam
        self.weight = weight
    }

    /// True when nothing is filled in.
    public var isEmpty: Bool {
        height == nil && waist == nil && bust == nil && hips == nil && inseam == nil && weight == nil
    }
}

/// A length with the unit she entered it in.
public struct Length: Hashable, Sendable, Codable {
    public var value: Double
    public var unit: Unit

    public init(_ value: Double, _ unit: Unit) {
        self.value = value
        self.unit = unit
    }

    public enum Unit: String, CaseIterable, Hashable, Sendable, Codable {
        case inches
        case centimeters
    }

    public var inches: Double {
        switch unit {
        case .inches: value
        case .centimeters: value / 2.54
        }
    }
}

/// A weight with the unit she entered it in.
public struct Weight: Hashable, Sendable, Codable {
    public var value: Double
    public var unit: Unit

    public init(_ value: Double, _ unit: Unit) {
        self.value = value
        self.unit = unit
    }

    public enum Unit: String, CaseIterable, Hashable, Sendable, Codable {
        case pounds
        case kilograms
    }

    public var pounds: Double {
        switch unit {
        case .pounds: value
        case .kilograms: value * 2.204_622_6
        }
    }
}

/// "Add a piece that fits you well" (LR-13): read as "Old Navy jeans · 0 Petite · Fits well".
///
/// Data tier: **Sensitive** (a fit reference, DATA_MAP.md).
public struct FitPiece: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = EntityID<FitPiece>

    public let id: ID
    public var brand: String
    public var category: GarmentCategory
    public var sizeLabel: String
    public var result: FitResult
    /// The closet piece it refers to, if any.
    public var garmentID: Garment.ID?

    public init(
        id: ID,
        brand: String,
        category: GarmentCategory,
        sizeLabel: String,
        result: FitResult = .fitsWell,
        garmentID: Garment.ID? = nil
    ) {
        self.id = id
        self.brand = brand
        self.category = category
        self.sizeLabel = sizeLabel
        self.result = result
        self.garmentID = garmentID
    }
}

/// How a piece fit her (PRD §10.1).
public enum FitResult: String, CaseIterable, Hashable, Sendable, Codable {
    case fitsWell
    case tooLong
    case tooShort
    case tooTight
    case tooLoose
}

/// Measurements never show their values in a string, so a stray `print`, a log line or a crash
/// report that interpolates them can't leak her body details (SECURITY_STANDARD §1 and §4: no
/// Sensitive data in logs). `dump` and debuggers see no children either.
extension BodyMeasurements: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        let filled = MeasurementField.allCases.count { checkedValue(of: $0) != nil }
        return "BodyMeasurements(redacted, \(filled) filled in)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror { Mirror(self, children: [Mirror.Child]()) }
}

// The parts of her fit details print no values either, so `"\(length)"`, `"\(piece)"` or a
// `dump` of one never shows a measurement, a brand or size she wears, or her usual fit.

extension Length: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "Length(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [Mirror.Child]()) }
}

extension Weight: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "Weight(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [Mirror.Child]()) }
}

extension FitPiece: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// The ID only, so a log line can still say which piece without saying what it is.
    public var description: String { "FitPiece(\(id), redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [Mirror.Child]()) }
}

/// Code that needs the word uses `rawValue` or `title`, never the description.
extension Comfort: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "Comfort(redacted)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [Mirror.Child]()) }
}
