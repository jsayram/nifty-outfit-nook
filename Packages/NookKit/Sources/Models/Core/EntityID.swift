import Foundation

/// A stable, typed identifier.
///
/// The `Entity` parameter only keeps IDs apart at compile time, so a garment ID can't be passed
/// where a look ID is expected. The value is a plain string: fixtures use readable ones such as
/// `g-navy-trousers`, and records created at run time get a UUID string. An ID never changes once
/// a record exists, and it encodes as a bare string.
public struct EntityID<Entity>: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// A new random ID, for records created at run time.
    public static func random() -> Self {
        Self(UUID().uuidString.lowercased())
    }

    public var description: String { rawValue }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension EntityID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}
