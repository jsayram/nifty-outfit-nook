import Foundation

/// Makes outfits. Stage A uses a mock (Fixtures); later the cloud stylist (Phase 27a) and the
/// on-device model (Phase 28) sit behind the same protocol.
///
/// The stylist gets a `StylingContext` the app built on the phone, and returns one base outfit
/// in up to three versions (LR-05a) with owned alternatives for each piece. The app checks the
/// result with `ResultCheck` before showing it. Failing to finish throws `StylistError`; it is
/// never reported as a small closet.
public protocol Stylist: Sendable {
    func style(_ context: StylingContext) async throws(StylistError) -> StyleOutcome
}

/// Why the weather couldn't be read. Style Me still works without it (LR-04.3).
public enum WeatherError: Error, Hashable, Sendable {
    case unavailable
    case cancelled
}

/// Today's weather. Fixtures in Stage A, WeatherKit in Phase 29 (once its capability is on).
public protocol WeatherProvider: Sendable {
    func currentWeather() async throws(WeatherError) -> WeatherSnapshot
    /// Apple Weather's credit, which has to show wherever its forecast does. `nil` when the
    /// weather isn't Apple's, so there's nothing to credit.
    func attribution() async -> WeatherCredit?
}

extension WeatherProvider {
    public func attribution() async -> WeatherCredit? { nil }
}

/// Why a picture couldn't be loaded.
public enum ImageError: Error, Hashable, Sendable {
    case unavailable
    case cancelled
}

/// Loads garment pictures. A placeholder until photos arrive (Phases 8 and 22): the Stage A
/// version has no pictures and returns `nil`, so screens draw their plain tile.
public protocol ImageProvider: Sendable {
    /// Image bytes no larger than `maxPixelSize` on the long side, or `nil` when there's no picture.
    func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data?
}

/// Why a try-on picture wasn't made. Nothing is kept and nothing is used either way.
public enum TryOnError: Error, Hashable, Sendable {
    /// No connection. Real pictures are made by a service (Phase 33).
    case offline
    /// The picture didn't finish.
    case notCompleted
    case cancelled
}

/// Makes a try-on picture of one look, only when she taps Try it on (RD-06.2).
///
/// Stage A's version (`SimulatedTryOn` in Fixtures) draws nothing and sends nothing: it returns a
/// `.simulated` picture, which the screens draw on the phone from the look's pieces, with no
/// person in it. Phase 33 puts the real, gated image service behind the same protocol, with its
/// permission, cost check and reuse of matching pictures (PRD §9.2, FR-59).
///
/// The screen keeps the picture in `TryOnPictureStore` before it says the picture is ready
/// (PRD §9.2.1 step 5).
public protocol TryOnService: Sendable {
    func makePicture(of look: Look, at date: Date) async throws(TryOnError) -> TryOnPicture
}
