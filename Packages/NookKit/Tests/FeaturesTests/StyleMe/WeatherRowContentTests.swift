import Foundation
import Models
import Testing

@testable import Features

/// What Style Me's Weather row and sheet say (LR-04).
struct WeatherRowContentTests {
    private let now = Date(timeIntervalSince1970: 1_791_000_000)
    private let us = Locale(identifier: "en_US")

    private func snapshot(_ condition: WeatherCondition, _ celsius: Double, night: Bool = false) -> WeatherSnapshot {
        WeatherSnapshot(condition: condition, temperatureCelsius: celsius, isNight: night, observedAt: now)
    }

    /// LR-04.1: "58° and rain", and the line under it.
    @Test func todaysWeatherShowsTemperatureAndCondition() {
        let content = WeatherRowContent(choice: .useToday, reading: .loaded(snapshot(.rain, 14.5)), locale: us)
        #expect(content.value == "58° and rain")
        #expect(content.explanation == "Your looks are picked for today’s weather.")
        #expect(content.systemImage == "cloud.rain")
        #expect(content.todayDetail == "58° and rain")
    }

    @Test func eachConditionInWords() {
        #expect(WeatherWords.summary(snapshot(.sun, 22.2), locale: us) == "72° and sunny")
        #expect(WeatherWords.summary(snapshot(.cloudy, 17.2), locale: us) == "63° and cloudy")
        #expect(WeatherWords.summary(snapshot(.snow, -1.1), locale: us) == "30° and snow")
        #expect(WeatherWords.summary(snapshot(.sun, 16.1, night: true), locale: us) == "61° and clear")
    }

    /// The temperature follows her locale's unit.
    @Test func celsiusWhereThatIsTheUnit() {
        let uk = Locale(identifier: "en_GB")
        #expect(WeatherWords.temperature(snapshot(.rain, 14.5), locale: uk).hasPrefix("14"))
        #expect(WeatherWords.temperature(snapshot(.rain, 14.5), locale: us).hasPrefix("58"))
    }

    /// LR-04.3: an honest message, and the row still works.
    @Test func unavailableWeatherSaysSo() {
        let content = WeatherRowContent(choice: .useToday, reading: .unavailable, locale: us)
        #expect(content.value == "Not available")
        #expect(content.explanation == "The weather can’t be read right now, so your looks won’t use it.")
        #expect(content.todayDetail == "Can’t be read right now")
    }

    @Test func loadingShowsAPlaceholder() {
        let content = WeatherRowContent(choice: .useToday, reading: .loading, locale: us)
        #expect(content.value == nil)
        #expect(content.todayDetail == "Checking the weather…")
    }

    /// The other two choices don't depend on the weather at all.
    @Test(arguments: [
        WeatherReading.loading, .unavailable,
        .loaded(
            WeatherSnapshot(
                condition: .snow, temperatureCelsius: -1, observedAt: .distantPast)),
    ])
    func indoorsAndIgnoreSayWhatTheyMean(_ reading: WeatherReading) {
        let indoors = WeatherRowContent(choice: .indoors, reading: reading, locale: us)
        #expect(indoors.value == "Indoors")
        #expect(indoors.explanation == "Your looks are picked for a day indoors.")
        #expect(indoors.systemImage == "house")
        let ignore = WeatherRowContent(choice: .ignore, reading: reading, locale: us)
        #expect(ignore.value == "Ignored")
        #expect(ignore.explanation == "Your looks don’t use the weather.")
    }

    @Test func choicesAreNamedAsInTheAmendment() {
        #expect(
            WeatherChoice.allCases.map(\.title) == ["Use today’s weather", "I’ll be indoors", "Ignore the weather"])
        #expect(Set(WeatherChoice.allCases.map(\.identifier)).count == 3)
    }
}
