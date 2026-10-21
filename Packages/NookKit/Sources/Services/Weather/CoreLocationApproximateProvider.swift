import CoreLocation
import Foundation
import Models

/// Her approximate location, for weather only (Phase 29).
///
/// The least that works: While Using the App only (never Always), reduced accuracy (the Info.plist
/// has `NSLocationDefaultAccuracyReduced`, and the manager asks for reduced accuracy too), one
/// fix at a time with no updates running, and the answer is rounded to a `CoarseCoordinate` before
/// it leaves this type. The raw fix is never kept, logged or passed on.
@MainActor
public final class CoreLocationApproximateProvider: NSObject, ApproximateLocationProvider, CLLocationManagerDelegate {
    /// How long to wait for a fix before giving up.
    static let timeout: Duration = .seconds(15)

    /// Made when first used, which is always on the main actor, so the provider itself can be
    /// created anywhere.
    private lazy var manager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        return manager
    }()
    private var asking: [CheckedContinuation<LocationAccess, Never>] = []
    private var finding: [CheckedContinuation<CoarseCoordinate?, Never>] = []

    nonisolated public override init() {
        super.init()
    }

    public func access() async -> LocationAccess {
        Self.access(for: manager.authorizationStatus)
    }

    public func requestAccess() async -> LocationAccess {
        guard manager.authorizationStatus == .notDetermined else { return await access() }
        return await withCheckedContinuation { continuation in
            asking.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    public func currentLocation() async throws(Models.WeatherError) -> CoarseCoordinate {
        guard await access() == .allowed else { throw .unavailable }
        let found = await withCheckedContinuation { (continuation: CheckedContinuation<CoarseCoordinate?, Never>) in
            let first = finding.isEmpty
            finding.append(continuation)
            guard first else { return }
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: Self.timeout)
                self?.finish(nil)
            }
        }
        guard let found else { throw .unavailable }
        return found
    }

    private static func access(for status: CLAuthorizationStatus) -> LocationAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: .allowed
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }

    private func finish(_ coordinate: CoarseCoordinate?) {
        let waiting = finding
        finding = []
        for continuation in waiting { continuation.resume(returning: coordinate) }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            let waiting = asking
            asking = []
            for continuation in waiting { continuation.resume(returning: Self.access(for: status)) }
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Rounded here, so the fix itself goes no further than this method.
        let rounded = locations.last.flatMap {
            CoarseCoordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        Task { @MainActor in finish(rounded) }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Task { @MainActor in finish(nil) }
    }
}
