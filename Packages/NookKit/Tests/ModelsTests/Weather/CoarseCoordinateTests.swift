import Foundation
import Models
import Testing

/// Phase 29: every coordinate the app keeps or sends is rounded to a tenth of a degree (about
/// 11 km), because location is Sensitive and weather doesn't need more (closet DATA_MAP F14).
struct CoarseCoordinateTests {
    @Test func roundsToATenthOfADegree() throws {
        let seattle = try #require(CoarseCoordinate(latitude: 47.60621, longitude: -122.33207))
        #expect(seattle.latitude == 47.6)
        #expect(seattle.longitude == -122.3)
    }

    @Test func nearbyStreetsShareOnePlace() throws {
        let one = try #require(CoarseCoordinate(latitude: 47.6205, longitude: -122.3493))
        let other = try #require(CoarseCoordinate(latitude: 47.6044, longitude: -122.3345))
        #expect(one == other)
    }

    @Test func roundingNeverKeepsMoreThanOneDecimal() throws {
        for (lat, lon) in [(51.50735, -0.12776), (-33.86882, 151.20929), (0.04999, -0.05001), (89.96, 179.96)] {
            let place = try #require(CoarseCoordinate(latitude: lat, longitude: lon))
            #expect(abs(place.latitude * 10 - (place.latitude * 10).rounded()) < 1e-9)
            #expect(abs(place.longitude * 10 - (place.longitude * 10).rounded()) < 1e-9)
        }
    }

    @Test func negativeZeroIsZero() throws {
        let place = try #require(CoarseCoordinate(latitude: -0.01, longitude: 0.02))
        #expect(place.latitude == 0 && place.latitude.sign == .plus)
        #expect(place == CoarseCoordinate(latitude: 0, longitude: 0))
    }

    @Test func rejectsWhatIsNotAPlace() {
        #expect(CoarseCoordinate(latitude: .nan, longitude: 0) == nil)
        #expect(CoarseCoordinate(latitude: 0, longitude: .infinity) == nil)
        #expect(CoarseCoordinate(latitude: 91, longitude: 0) == nil)
        #expect(CoarseCoordinate(latitude: 0, longitude: -181) == nil)
    }

    @Test func roundingIsStable() throws {
        let once = try #require(CoarseCoordinate(latitude: 47.60621, longitude: -122.33207))
        let twice = try #require(CoarseCoordinate(latitude: once.latitude, longitude: once.longitude))
        #expect(once == twice)
    }

    /// A stored value that was edited to be precise is rounded when it's read back.
    @Test func decodingRoundsToo() throws {
        let json = Data(#"{"latitude": 47.606209, "longitude": -122.332071}"#.utf8)
        let place = try JSONDecoder().decode(CoarseCoordinate.self, from: json)
        #expect(place.latitude == 47.6 && place.longitude == -122.3)
        let bad = Data(#"{"latitude": 200, "longitude": 0}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(CoarseCoordinate.self, from: bad) }
    }

    @Test func storedSettingsNeverHoldAPreciseCoordinate() throws {
        let point = try #require(CoarseCoordinate(latitude: 47.60621, longitude: -122.33207))
        let settings = WeatherSettings(
            isOn: true, usesMyLocation: false, city: WeatherPlace(name: "  Seattle, WA ", coordinate: point))
        let text = try #require(String(data: try JSONEncoder().encode(settings), encoding: .utf8))
        #expect(!text.contains("47.60621") && !text.contains("122.33207"))
        #expect(text.contains("Seattle, WA"))
        #expect(!text.contains("  Seattle"))
    }

    @Test func placeNeedsAName() throws {
        let point = try #require(CoarseCoordinate(latitude: 1, longitude: 1))
        #expect(WeatherPlace(name: "   ", coordinate: point) == nil)
        let long = try #require(WeatherPlace(name: String(repeating: "a", count: 300), coordinate: point))
        #expect(long.name.count == WeatherPlace.nameLimit)
    }
}
