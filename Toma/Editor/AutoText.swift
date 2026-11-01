import CoreLocation
import Foundation

/// Textos automáticos: momento del día, hora, fecha y feeling.
enum AutoText {
    static func timeOfDay(_ date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<8: return "sunrise"
        case 8..<12: return "good morning"
        case 12..<17: return "afternoon"
        case 17..<19: return "golden hour"
        case 19..<21: return "blue hour"
        default: return "late night"
        }
    }

    static func clock(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    static func dayText(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd · MM · yyyy"
        return formatter.string(from: date)
    }

    static let feelings: [String] = [
        "chill", "grateful & blessed", "modo maestro", "gym mode", "swim day",
        "good vibes", "soft life", "on my way", "main character", "hecho en México"
    ]
}

/// Ubicación actual o de la foto convertida en "Ciudad, Estado".
final class LocationHelper: NSObject, CLLocationManagerDelegate {
    static let shared = LocationHelper()
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    func placeName(for location: CLLocation?) async -> String? {
        let resolved: CLLocation?
        if let location {
            resolved = location
        } else {
            resolved = await currentLocation()
        }
        guard let resolved else { return nil }
        let marks = try? await CLGeocoder().reverseGeocodeLocation(resolved, preferredLocale: Locale(identifier: "es_MX"))
        guard let place = marks?.first else { return nil }
        let parts = [place.locality ?? place.subAdministrativeArea, place.administrativeArea].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func currentLocation() async -> CLLocation? {
        await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            DispatchQueue.main.async {
                self.continuation?.resume(returning: nil)
                self.continuation = cont
                self.manager.delegate = self
                self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                switch self.manager.authorizationStatus {
                case .notDetermined:
                    self.manager.requestWhenInUseAuthorization()
                case .authorizedWhenInUse, .authorizedAlways:
                    self.manager.requestLocation()
                default:
                    self.finish(nil)
                }
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }
}
