import Foundation
import CoreLocation
import MapKit

/// The time zone of the place a fix is in, by Apple's reverse geocoder (brief 83): one request per fix, at most one
/// an hour, so the companion keeps the hours of where the person is (`CompanionSkySource.setTimeZone`). WeatherKit's
/// answer carries no zone, so this is the cheapest honest way: the same approximate fix that went to Apple Weather
/// goes to Apple's geocoder, and only the zone comes back into the app (the placemark is dropped).
///
/// MapKit's `MKReverseGeocodingRequest` on iOS and macOS 26 and later; Core Location's `CLGeocoder` (deprecated in
/// 26) before that. No key or entitlement: the app's network access is enough.
@MainActor
final class GeocoderZoneSource: WeatherZoneSource {
    func timeZone(at location: CLLocation) async throws -> TimeZone? {
        if #available(iOS 26.0, macOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            let items = try await request.mapItems
            return items.lazy.compactMap(\.timeZone).first
        } else {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
            return placemarks.lazy.compactMap(\.timeZone).first
        }
    }
}
