import Foundation
import Models
import Testing

/// Phase 29: the weather in a styling request is a short summary, with nothing about where she is.
struct WeatherSummaryTests {
    private let snapshot = WeatherSnapshot(
        condition: .rain, temperatureCelsius: 14.5, isNight: false, observedAt: Date(timeIntervalSince1970: 1_000),
        lowCelsius: 9.4, highCelsius: 16.6, precipitationChance: 0.64)

    @Test func carriesConditionsRangeAndChance() {
        let summary = snapshot.summary
        #expect(summary.condition == .rain)
        #expect(summary.temperatureCelsius == 15)
        #expect(summary.lowCelsius == 9)
        #expect(summary.highCelsius == 17)
        #expect(summary.precipitationPercent == 60)
        #expect(summary.isNight == false)
    }

    @Test func chanceIsRoundedToTens() {
        func percent(_ chance: Double) -> Int? {
            WeatherSnapshot(
                condition: .cloudy, temperatureCelsius: 10, observedAt: .distantPast, precipitationChance: chance
            )
            .summary.precipitationPercent
        }
        #expect(percent(0) == 0)
        #expect(percent(0.04) == 0)
        #expect(percent(0.05) == 10)
        #expect(percent(0.96) == 100)
        // The snapshot keeps a chance in range whatever the service says.
        #expect(percent(3) == 100)
        #expect(percent(-1) == 0)
    }

    @Test func missingPartsStayMissing() {
        let plain = WeatherSnapshot(condition: .sun, temperatureCelsius: 22, observedAt: .distantPast).summary
        #expect(plain.lowCelsius == nil && plain.highCelsius == nil && plain.precipitationPercent == nil)
    }

    /// The exact keys that may be sent. A new key here means a new thing leaves the phone: it
    /// needs a DATA_MAP.md row first.
    @Test func theShapeIsFixedAndHasNoPlaceInIt() throws {
        let data = try JSONEncoder().encode(snapshot.summary)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(
            Set(object.keys)
                == ["condition", "temperatureCelsius", "lowCelsius", "highCelsius", "precipitationPercent", "isNight"])
        let text = try #require(String(data: data, encoding: .utf8)).lowercased()
        for word in ["latitude", "longitude", "coordinate", "city", "place", "observedat", "location"] {
            #expect(!text.contains(word))
        }
    }

    @Test func oldSnapshotsStillDecode() throws {
        let json = Data(
            #"{"condition":"sun","temperatureCelsius":20,"isNight":false,"observedAt":0}"#.utf8)
        let old = try JSONDecoder().decode(WeatherSnapshot.self, from: json)
        #expect(old.lowCelsius == nil && old.precipitationChance == nil)
    }
}
