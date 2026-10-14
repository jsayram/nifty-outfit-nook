import Foundation
import Models

/// A `WeatherProvider` that returns a fixed snapshot, or fails like an offline phone.
public struct FixtureWeatherProvider: WeatherProvider {
    public var snapshot: WeatherSnapshot
    public var isOffline: Bool
    public var latency: Duration

    public init(snapshot: WeatherSnapshot, isOffline: Bool = false, latency: Duration = .zero) {
        self.snapshot = snapshot
        self.isOffline = isOffline
        self.latency = latency
    }

    public func currentWeather() async throws(WeatherError) -> WeatherSnapshot {
        if latency > .zero {
            do {
                try await Task.sleep(for: latency)
            } catch {
                throw .cancelled
            }
        }
        if isOffline { throw .unavailable }
        return snapshot
    }
}

/// An `ImageProvider` with no pictures. Stage A has no photos, so screens draw their plain tile.
public struct PlaceholderImageProvider: ImageProvider {
    public init() {}

    public func imageData(for reference: PhotoReference, maxPixelSize: Int) async throws(ImageError) -> Data? {
        nil
    }
}
