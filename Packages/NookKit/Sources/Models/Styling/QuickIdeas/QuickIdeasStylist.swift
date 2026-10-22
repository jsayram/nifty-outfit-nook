import Foundation

/// Quick ideas (Phase 28): the stylist on the phone, always there. It answers when the cloud
/// stylist can't (offline, no consent, the stylist paused or her allowance used up, or no backend
/// at all), and on any iPhone, because it needs no model: Lily's iPhone 12 can't run Apple's
/// on-device model (`docs/decisions/0010-on-device-stylist.md`).
///
/// It returns the same typed result as the cloud stylist (`StyleOutcome`, checked by
/// `ResultCheck`), with a "why" line per version written from templates, and marks the result as
/// made on the phone (`StyleResult.madeBy`), so Your looks can say so honestly.
///
/// The matching is plain and generic, on stored facts only: occasion tags and dressiness against
/// the occasion, warmth against the weather band, a common neutrals-plus-one-colour palette check,
/// her comfort and colour wish, and what she wore lately. Nothing about her body, and none of the
/// fit or styling rules or prompts, which stay in the private backend (SECURITY_STANDARD.md §3).
/// Deterministic: the same context always gives the same result.
public struct QuickIdeasStylist: Stylist {
    /// Writes a version's "why" line. The words live with the screens (Features), so Models holds
    /// no user-facing text.
    public typealias WhyWriter = @Sendable (QuickIdeasWhy) -> String

    private let writeWhy: WhyWriter

    public init(why: @escaping WhyWriter) {
        writeWhy = why
    }

    public func style(_ context: StylingContext) async throws(StylistError) -> StyleOutcome {
        if Task.isCancelled { throw .cancelled }
        return QuickIdeas(context: context).outcome(why: writeWhy)
    }
}

/// What a quick idea's "why" line is about, for the templates that write it.
public struct QuickIdeasWhy: Hashable, Sendable {
    public enum Weather: Hashable, Sendable {
        /// Today's weather in use: the band, and whether it's raining or snowing.
        case outdoors(TemperatureBand, wet: Bool)
        /// Indoors, ignored, or today's weather couldn't be read.
        case notUsed
    }

    public enum Palette: Hashable, Sendable {
        /// Only neutrals (black, white, cream, beige, tan, brown, gray, navy, denim).
        case neutrals
        /// Neutrals and one colour family.
        case neutralsAnd(ColorName)
        /// More than one colour, or a print.
        case mixed
    }

    /// What a version changed from Simple.
    public enum Change: Hashable, Sendable {
        /// Simple itself.
        case none
        /// Dressed up: a dressier piece of this kind.
        case dressier(GarmentCategory)
        /// Something new: another of her pieces of this kind.
        case another(GarmentCategory)
        /// Something new: one idea piece to try.
        case idea(PieceIdea)
    }

    public var version: LookVersion
    public var occasion: Occasion
    public var weather: Weather
    /// A layer was added for the weather (not a starting piece).
    public var addsLayer: Bool
    public var palette: Palette
    public var change: Change

    public init(
        version: LookVersion, occasion: Occasion, weather: Weather, addsLayer: Bool, palette: Palette, change: Change
    ) {
        self.version = version
        self.occasion = occasion
        self.weather = weather
        self.addsLayer = addsLayer
        self.palette = palette
        self.change = change
    }
}
