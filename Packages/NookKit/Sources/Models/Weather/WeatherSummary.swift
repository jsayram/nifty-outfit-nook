import Foundation

/// The only weather that leaves the phone for the stylist (Phase 29): a short description of the
/// day. No place, no coordinates and no time, so there is nothing in it to say where she is.
///
/// The temperatures are whole degrees Celsius and the chance of precipitation is rounded to the
/// nearest 10 percent, because the stylist can't use more than that and a coarse value reveals
/// less. The shape is fixed, and a test checks its keys.
public struct WeatherSummary: Hashable, Sendable, Codable {
    public var condition: WeatherCondition
    public var temperatureCelsius: Int
    public var lowCelsius: Int?
    public var highCelsius: Int?
    /// 0 to 100, in steps of 10.
    public var precipitationPercent: Int?
    public var isNight: Bool

    public init(_ snapshot: WeatherSnapshot) {
        condition = snapshot.condition
        temperatureCelsius = Int(snapshot.temperatureCelsius.rounded())
        lowCelsius = snapshot.lowCelsius.map { Int($0.rounded()) }
        highCelsius = snapshot.highCelsius.map { Int($0.rounded()) }
        precipitationPercent = snapshot.precipitationChance.map { Int(($0 * 10).rounded()) * 10 }
        isNight = snapshot.isNight
    }
}
