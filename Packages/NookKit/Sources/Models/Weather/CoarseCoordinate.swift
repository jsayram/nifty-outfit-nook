import Foundation

/// A place on the map, rounded to a tenth of a degree (about 11 km, a city and not a street).
///
/// Weather doesn't need more, and location is **Sensitive** (closet `DATA_MAP.md`, F14). Every
/// coordinate the app keeps, caches or hands to the weather service goes through this type, so a
/// precise one can't be held by accident: the only initializer rounds, and so does decoding, so
/// a stored value that was edited to be precise reads back rounded.
public struct CoarseCoordinate: Hashable, Sendable, Codable {
    /// The size of one step, in degrees.
    public static let step = 0.1

    public let latitude: Double
    public let longitude: Double

    /// `nil` for anything that isn't a place on Earth: not a number, or out of range.
    public init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude),
            (-180...180).contains(longitude)
        else { return nil }
        self.latitude = Self.round(latitude)
        self.longitude = Self.round(longitude)
    }

    private static func round(_ value: Double) -> Double {
        let rounded = (value / step).rounded() / (1 / step)
        // -0.0 and 0.0 are the same place, and the same cache key.
        return rounded == 0 ? 0 : rounded
    }

    private enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        guard let coarse = CoarseCoordinate(latitude: latitude, longitude: longitude) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not a place on Earth."))
        }
        self = coarse
    }
}
