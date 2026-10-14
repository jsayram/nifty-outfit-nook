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

/// Today's weather. Fixtures in Stage A, WeatherKit in Phase 29.
public protocol WeatherProvider: Sendable {
    func currentWeather() async throws(WeatherError) -> WeatherSnapshot
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
