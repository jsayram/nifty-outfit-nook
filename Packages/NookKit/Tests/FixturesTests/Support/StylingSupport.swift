import Foundation
import Models

/// A fixed calendar and date, so tests don't depend on the Mac's time zone or today's date.
enum TestTime {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Noon UTC on 14 October 2026.
    static let now = Date(timeIntervalSince1970: 1_791_979_200)

    /// `offset` days from `now`, same time of day.
    static func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: now) ?? now
    }
}

extension StylingContext {
    /// A context built from fixture data, the way a screen will build it.
    static func from(
        _ data: FixtureDataLike,
        request: StyleRequest,
        now: Date = TestTime.now
    ) throws(StylingContextError) -> StylingContext {
        try StylingContext.make(
            request: request,
            garments: data.garments,
            suitcases: data.suitcases,
            looks: data.looks,
            usualFit: data.profile.usualFit,
            now: now,
            calendar: TestTime.calendar
        )
    }
}

/// The parts of `FixtureData` a context needs, so tests can also pass hand-built closets.
protocol FixtureDataLike {
    var garments: [Garment] { get }
    var suitcases: [Suitcase] { get }
    var looks: [Look] { get }
    var profile: Profile { get }
}

func makeRequest(
    _ id: StyleRequest.ID = "req-1",
    source: WardrobeSource = .mainCloset,
    occasion: Occasion = .office,
    weatherChoice: WeatherChoice = .useToday,
    pieceMode: PieceMode = .mineAndOneIdea,
    repeatWindow: RepeatWindow = .oneWeek,
    tracksLaundry: Bool = false,
    startingPieceID: Garment.ID? = nil
) -> StyleRequest {
    StyleRequest(
        id: id,
        source: source,
        occasion: occasion,
        weatherChoice: weatherChoice,
        weather: WeatherSnapshot(condition: .rain, temperatureCelsius: 14.5, observedAt: TestTime.now),
        preferences: Preferences(pieceMode: pieceMode, repeatWindow: repeatWindow, tracksLaundry: tracksLaundry),
        startingPieceID: startingPieceID,
        createdAt: TestTime.now
    )
}
