import MapKit

/// Calculates travel only for the selected plan. This keeps generation economical and avoids
/// flooding MapKit with direction requests for plans that will never be selected.
enum DateTransferResolver {
    static func resolve(stations: [DateStation], mobility: Mobility, startingAt: Date) async -> [DateStation] {
        var result = stations.sorted { $0.order < $1.order }
        var departure = startingAt
        for index in result.indices {
            guard !Task.isCancelled else { break }
            if index > 0, result[index].arrivalTransfer == nil,
               let from = result[index - 1].resolvedPlace, let to = result[index].resolvedPlace {
                result[index].arrivalTransfer = await transfer(from: from, to: to, mobility: mobility, departure: departure)
                departure = departure.addingTimeInterval(Double(result[index].arrivalTransfer?.minutes ?? 0) * 60)
            }
            departure = departure.addingTimeInterval(Double(result[index].estimatedDurationMinutes) * 60)
        }
        return result
    }

    private static func transfer(from: ResolvedPlace, to: ResolvedPlace, mobility: Mobility, departure: Date) async -> DateTransfer? {
        let source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: from.latitude, longitude: from.longitude)))
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: to.latitude, longitude: to.longitude)))
        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.departureDate = departure
        request.transportType = mobility == .auto ? .automobile : mobility == .oepnv ? .transit : .walking
        let directions = MKDirections(request: request)
        // ETA supports transit as well. An unavailable transit route remains unknown; a straight
        // line divided by a speed would be a particularly misleading transit estimate.
        defer { directions.cancel() }
        guard let eta = try? await withTimeout(seconds: 6, operation: { try await directions.calculateETA() }),
              eta.expectedTravelTime.isFinite, eta.expectedTravelTime >= 0 else { return nil }
        return DateTransfer(minutes: max(1, Int(ceil(eta.expectedTravelTime / 60))), distanceMeters: eta.distance,
                            transport: mobility.label, isEstimate: true)
    }
}
