import CoreLocation
import Foundation
import MapKit

/// Wraps CoreLocation for the two things the criteria form and MapKit resolution need: the
/// current coordinate, and a reverse-geocoded city name to prefill the "Stadt" field. Never
/// requests location proactively without the form asking for it — the usage-description string
/// in Info.plist frames this as form-assist, so it should behave that way.
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum LocationError: LocalizedError {
        case denied
        case unavailable

        var errorDescription: String? {
            switch self {
            case .denied: return "Standortzugriff wurde nicht erlaubt. Du kannst die Stadt auch manuell eingeben."
            case .unavailable: return "Standort konnte nicht ermittelt werden."
            }
        }
    }

    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func requestCurrentCity() async throws -> String {
        if authorizationStatus == .notDetermined {
            _ = await requestAuthorization()
        }
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            throw LocationError.denied
        }
        let location = try await currentLocation()
        return try await reverseGeocode(location)
    }

    private func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            authContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    private func currentLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> String {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let city = placemarks.first?.locality else {
            throw LocationError.unavailable
        }
        return city
    }

    /// Forward-geocodes the form's free-text city into a coordinate for MKLocalSearch's region —
    /// the criteria form only ever stores a city name, never a coordinate, since it must stay
    /// editable as plain text.
    static func geocodeCity(_ city: String) async throws -> CLLocationCoordinate2D {
        let normalizedCity = normalizedCityName(city)
        guard normalizedCity.count >= 2 else { throw LocationError.unavailable }

        // CLGeocoder is fast when it is available, but it intermittently returns no result in
        // the Simulator even for ordinary cities such as Marburg. Try the plain city first and
        // then add the country, because an international city name alone can be ambiguous.
        let geocoder = CLGeocoder()
        for query in [normalizedCity, "\(normalizedCity), Deutschland"] {
            if let placemarks = try? await geocoder.geocodeAddressString(query),
               let coordinate = placemarks.first?.location?.coordinate {
                return coordinate
            }
        }

        // MapKit has a separate search index from CLGeocoder. This is the same family of lookup
        // that powers our city picker, and gives the planner a second reliable path on device.
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(normalizedCity), Deutschland"
        request.resultTypes = [.address]
        if let response = try? await MKLocalSearch(request: request).start(),
           let coordinate = response.mapItems.first?.placemark.coordinate,
           CLLocationCoordinate2DIsValid(coordinate) {
            return coordinate
        }

        // A tiny offline safety net keeps the seeded local experience usable if the Simulator's
        // Apple geocoding services are temporarily unavailable. It is intentionally only a
        // last resort; all other cities still use the live geocoder and MapKit search above.
        if let coordinate = localFallbackCities[normalizedCity.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)] {
            return coordinate
        }

        throw LocationError.unavailable
    }

    nonisolated static func normalizedCityName(_ city: String) -> String {
        city
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'„“‚‘"))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static let localFallbackCities: [String: CLLocationCoordinate2D] = [
        "marburg": CLLocationCoordinate2D(latitude: 50.8070, longitude: 8.7700),
        "marburg an der lahn": CLLocationCoordinate2D(latitude: 50.8070, longitude: 8.7700),
    ]

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            authContinuation?.resume(returning: manager.authorizationStatus)
            authContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }
}
