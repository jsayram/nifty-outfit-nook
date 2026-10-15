import Foundation

/// What she asked Style Me for. Built when she taps Style me (RD-02).
///
/// Data tier: **Sensitive** when it carries today's comfort, otherwise **Personal**
/// (DATA_MAP.md, "Cloud styling request"). Comfort, colour and weather choice apply to this
/// request only; the next new request starts from the defaults again (FR-05, LR-04).
public struct StyleRequest: Identifiable, Hashable, Sendable, Codable {
    public typealias ID = EntityID<StyleRequest>

    public let id: ID
    public var source: WardrobeSource
    public var occasion: Occasion
    /// Her words for an Other occasion ("museum visit"), trimmed, at most
    /// `NameRules.occasionNoteMaximum` characters. `nil` for every other occasion. Kept with this
    /// request only. **Personal** free text: the stylist treats it as data, never instructions.
    public var occasionNote: String?
    /// Use today's weather, I'll be indoors, or Ignore the weather (LR-04).
    public var weatherChoice: WeatherChoice
    /// The weather when the request was made. `nil` when it couldn't be read (LR-04.3).
    public var weather: WeatherSnapshot?
    /// Today's comfort, "Just for this outfit" (LR-18). `nil` means her usual fit.
    public var comfort: Comfort?
    /// A colour she'd like in the look: preferred or required, and where (PRD §8.3, FR-48).
    public var color: ColorWish?
    /// Her preferences when the request was made.
    public var preferences: Preferences
    /// "Style with this": a piece every version must include.
    public var startingPieceID: Garment.ID?
    public var createdAt: Date

    public init(
        id: ID,
        source: WardrobeSource = .mainCloset,
        occasion: Occasion,
        occasionNote: String? = nil,
        weatherChoice: WeatherChoice = .useToday,
        weather: WeatherSnapshot? = nil,
        comfort: Comfort? = nil,
        color: ColorWish? = nil,
        preferences: Preferences = Preferences(),
        startingPieceID: Garment.ID? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.source = source
        self.occasion = occasion
        self.occasionNote = occasionNote
        self.weatherChoice = weatherChoice
        self.weather = weather
        self.comfort = comfort
        self.color = color
        self.preferences = preferences
        self.startingPieceID = startingPieceID
        self.createdAt = createdAt
    }

    /// Whether Something new may add one piece she doesn't own.
    ///
    /// Only with Mine + one idea and the main closet. A suitcase source always styles from owned
    /// pieces only, whatever Preferences says (PRD §7.7 and §8.1, LR-05b).
    public var allowsNewPieceIdea: Bool {
        preferences.pieceMode == .mineAndOneIdea && !source.isSuitcase
    }

    /// The weather that should shape the look, or `nil` when she's indoors, ignoring it, or it
    /// couldn't be read.
    public var weatherToUse: WeatherSnapshot? {
        weatherChoice == .useToday ? weather : nil
    }
}

/// The Weather sheet's three choices (LR-04). Request-scoped, like Comfort.
public enum WeatherChoice: String, CaseIterable, Hashable, Sendable, Codable {
    case useToday
    case indoors
    case ignore
}

/// Weather for today, from the weather service (fixtures in Stage A, WeatherKit in Phase 29).
///
/// Data tier: the forecast is **Public**. Location is never part of it.
public struct WeatherSnapshot: Hashable, Sendable, Codable {
    public var condition: WeatherCondition
    public var temperatureCelsius: Double
    /// After dark. Home shows the night window (RD-01).
    public var isNight: Bool
    public var observedAt: Date

    public init(condition: WeatherCondition, temperatureCelsius: Double, isNight: Bool = false, observedAt: Date) {
        self.condition = condition
        self.temperatureCelsius = temperatureCelsius
        self.isNight = isNight
        self.observedAt = observedAt
    }

    /// A rough temperature band, used to match a garment's warmth.
    public var band: TemperatureBand {
        switch temperatureCelsius {
        case ..<10: .cold
        case ..<18: .cool
        case ..<26: .mild
        default: .hot
        }
    }
}

/// The weather states the Home window can show (RD-01).
public enum WeatherCondition: String, CaseIterable, Hashable, Sendable, Codable {
    case sun
    case cloudy
    case rain
    case snow
}

/// Temperature bands for matching garment warmth.
public enum TemperatureBand: String, CaseIterable, Hashable, Sendable, Codable {
    case cold
    case cool
    case mild
    case hot

    /// Garment warmth that suits this band. A plain lookup on stored facts, not a styling rule.
    public var suitableWarmth: Set<Warmth> {
        switch self {
        case .cold: [.warm]
        case .cool: [.medium, .warm]
        case .mild: [.light, .medium]
        case .hot: [.light]
        }
    }
}
