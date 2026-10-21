import CoreLocation
import Foundation
import MapKit
import Models

/// Finds a city by the name she types, through Apple Maps (Phase 29). It needs no location
/// permission: the words she types go to Apple's geocoder, and the answer is a name and a point
/// that's rounded the moment it arrives, so a street address comes out as its city's area.
public struct MapKitCityFinder: CityFinder {
    public static let queryLimit = 80
    public static let resultLimit = 5

    public init() {}

    @MainActor
    public func cities(matching query: String) async throws(Models.WeatherError) -> [WeatherPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }
        guard let request = MKGeocodingRequest(addressString: String(trimmed.prefix(Self.queryLimit))) else {
            return []
        }
        let items: [MKMapItem]
        do {
            items = try await request.mapItems
        } catch is CancellationError {
            throw .cancelled
        } catch {
            // No match comes back as an error too; either way there is nothing to show.
            let code = (error as NSError).code
            if (error as NSError).domain == MKError.errorDomain, code == MKError.placemarkNotFound.rawValue {
                return []
            }
            throw .unavailable
        }
        var seen = Set<String>()
        var places: [WeatherPlace] = []
        for item in items {
            let name = item.addressRepresentations?.cityWithContext ?? item.name ?? ""
            let point = item.location.coordinate
            guard let coordinate = CoarseCoordinate(latitude: point.latitude, longitude: point.longitude),
                let place = WeatherPlace(name: name, coordinate: coordinate),
                seen.insert(place.name).inserted
            else { continue }
            places.append(place)
            if places.count == Self.resultLimit { break }
        }
        return places
    }
}
