import CoreLocation
import Foundation

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var currentCity: String? = nil

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var pendingContinuation: CheckedContinuation<String?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestInitialAuthorization() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func requestCityIfAuthorized() {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func requestCityOnce() async -> String? {
        if let cached = currentCity, !cached.isEmpty {
            return cached
        }
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            return nil
        }
        return await withCheckedContinuation { cont in
            self.pendingContinuation = cont
            if status == .notDetermined {
                manager.requestWhenInUseAuthorization()
            } else {
                manager.requestLocation()
            }
            // Safety timeout (3.5s) so chat never stalls waiting for GPS
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(3500))
                if let c = self?.pendingContinuation {
                    self?.pendingContinuation = nil
                    c.resume(returning: self?.currentCity)
                }
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let st = manager.authorizationStatus
            if st == .authorizedWhenInUse || st == .authorizedAlways {
                manager.requestLocation()
            } else if st == .denied || st == .restricted {
                if let c = pendingContinuation {
                    pendingContinuation = nil
                    c.resume(returning: nil)
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        Task { @MainActor in
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "tr_TR"))
                let city = placemarks.first?.administrativeArea ?? placemarks.first?.locality
                self.currentCity = city
                if let c = pendingContinuation {
                    pendingContinuation = nil
                    c.resume(returning: city)
                }
            } catch {
                if let c = pendingContinuation {
                    pendingContinuation = nil
                    c.resume(returning: nil)
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            if let c = pendingContinuation {
                pendingContinuation = nil
                c.resume(returning: currentCity)
            }
        }
    }
}
