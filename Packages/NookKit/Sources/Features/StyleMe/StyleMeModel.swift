import Foundation
import Models
import Observation

/// The Style Me request screen's state (RD-02): what she has chosen, checked against her closet
/// on every change, and the request it becomes when she taps Style me.
///
/// Opening Style Me sends nothing (RD-02.1). The draft lives as long as the screen: a new Style Me
/// starts from the defaults again, so Comfort, Color and Weather reset (RD-02.4, LR-04.2, LR-18.2).
/// The checking and building are `StyleRequestBuilder`'s, a pure rule in Models.
@Observable
final class StyleMeModel {
    enum Phase: Equatable {
        case loading
        case loaded
        /// A store failed. The screen shows its error state with Try again.
        case failed
    }

    private(set) var phase: Phase = .loading
    private(set) var draft: StyleRequestDraft
    /// The draft checked against her closet. Updated with every change.
    private(set) var check = StyleRequestCheck(issues: [], piecesInSource: 0, usablePieces: 0)
    private(set) var builder: StyleRequestBuilder?
    private(set) var weather: WeatherReading = .loading
    /// Her usual fit from Profile, for the Comfort line (LR-18).
    private(set) var usualFit: Comfort?
    /// True once the draft has been set up from her preferences, so a reload keeps her choices.
    private var hasDraft = false

    /// - Parameter startingPieceID: from a garment's "Style with this" (amendment, decision 2).
    init(startingPieceID: Garment.ID? = nil) {
        draft = StyleRequestDraft(preferences: Preferences(), startingPieceID: startingPieceID)
    }

    // MARK: Loading

    /// Loads her closet, suitcases and profile, and the weather alongside them. Weather that
    /// can't be read isn't a failure (LR-04.3). Loading again, for example after adding a piece,
    /// keeps what she has chosen.
    func load(from services: NookServices?, now: Date = .now) async {
        guard let services else {
            weather = .unavailable
            phase = .failed
            return
        }
        if builder == nil { phase = .loading }
        async let reading = Self.currentWeather(from: services)
        do {
            async let garments = services.closet.garments()
            async let suitcases = services.suitcases.suitcases()
            async let profile = services.profile.profile()
            show(garments: try await garments, suitcases: try await suitcases, profile: try await profile, now: now)
        } catch {
            if builder == nil { phase = .failed }
        }
        weather = await reading
    }

    /// Sets everything from loaded data. Separate from `load` so tests can hand data straight in.
    func show(garments: [Garment], suitcases: [Suitcase], profile: Profile, now: Date) {
        builder = StyleRequestBuilder(
            garments: garments, suitcases: suitcases, preferences: profile.preferences, now: now)
        usualFit = profile.usualFit
        if !hasDraft {
            draft = StyleRequestDraft(
                preferences: profile.preferences, source: draft.source, occasion: draft.occasion,
                startingPieceID: draft.startingPieceID)
            hasDraft = true
        }
        recheck()
        phase = .loaded
    }

    func showWeather(_ reading: WeatherReading) {
        weather = reading
    }

    private static func currentWeather(from services: NookServices) async -> WeatherReading {
        do {
            return .loaded(try await services.weather.currentWeather())
        } catch {
            return .unavailable
        }
    }

    // MARK: Choices

    /// Changes the draft and checks it again.
    func update(_ change: (inout StyleRequestDraft) -> Void) {
        change(&draft)
        recheck()
    }

    /// A new source. A starting piece that isn't in it stays, and the screen says so, so she
    /// never loses a choice without seeing why.
    func choose(source: WardrobeSource) {
        update { $0.source = source }
    }

    private func recheck() {
        guard let builder else { return }
        check = builder.check(draft)
    }

    // MARK: What the screen shows

    var startingPiece: Garment? {
        draft.startingPieceID.flatMap { builder?.garment($0) }
    }

    var suitcase: Suitcase? {
        builder?.suitcase(for: draft.source)
    }

    /// The pieces the starting piece sheet offers: usable ones from the source.
    var startingPieceChoices: [Garment] {
        builder?.usablePieces(in: draft.source) ?? []
    }

    var activeSuitcases: [Suitcase] {
        builder?.activeSuitcases ?? []
    }

    /// Pieces in a source, for the Source sheet.
    func pieceCount(in source: WardrobeSource) -> Int {
        builder?.pieces(in: source).count ?? 0
    }

    var canStyle: Bool {
        phase == .loaded && check.canStyle
    }

    /// The words on the screen.
    func text(locale: Locale = .current) -> StyleMeText {
        StyleMeText(
            draft: draft, check: check, startingPiece: startingPiece, suitcaseName: suitcase?.name,
            usualFit: usualFit, locale: locale)
    }

    // MARK: Style me

    /// The request, when nothing stops it. Opening the results is the only thing that sends it
    /// (RD-02.1).
    func makeRequest(id: StyleRequest.ID = .random(), now: Date = .now) -> StyleRequest? {
        guard phase == .loaded, let builder else { return nil }
        return try? builder.build(draft, weather: weather.snapshot, id: id, createdAt: now)
    }
}
