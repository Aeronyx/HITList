import Foundation
import CoreLocation

/// The device's approximate location through Core Location (brief 80): permission while in use, reduced accuracy (a
/// town is plenty; `NSLocationDefaultAccuracyReduced` makes the prompt offer only that), one fix at a time, never
/// updates in the background. Made only once the person has switched Weather on (`CompanionWeather` creates it
/// lazily), so with the setting off, never asked, the app never touches Core Location.
///
/// The fix is handed to the caller and forgotten: nothing here keeps, logs or sends it.
@MainActor
final class CoreLocationSource: NSObject, WeatherLocationSource {
    /// A fix that has not arrived by then has failed (the service backs off to the next time the app comes forward).
    static let fixTimeout: Duration = .seconds(30)

    private let manager = CLLocationManager()
    private var accessWaiters: [CheckedContinuation<WeatherAccess, Never>] = []
    private var fixWaiters: [CheckedContinuation<CLLocation, Error>] = []
    private var timeout: Task<Void, Never>?

    struct NoFix: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyReduced
        manager.delegate = self
    }

    func access() -> WeatherAccess { Self.access(manager.authorizationStatus) }

    nonisolated static func access(_ status: CLAuthorizationStatus) -> WeatherAccess {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedAlways, .authorizedWhenInUse: .allowed
        @unknown default: .denied
        }
    }

    func requestAccess() async -> WeatherAccess {
        let current = access()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            accessWaiters.append(continuation)
            if accessWaiters.count == 1 { manager.requestWhenInUseAuthorization() }
        }
    }

    func approximateLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            fixWaiters.append(continuation)
            guard fixWaiters.count == 1 else { return }
            manager.requestLocation()
            timeout = Task { [weak self] in
                try? await Task.sleep(for: Self.fixTimeout)
                guard !Task.isCancelled else { return }
                self?.finishFix(.failure(NoFix(reason: "no location within \(Self.fixTimeout)")))
            }
        }
    }

    private func finishFix(_ result: Result<CLLocation, Error>) {
        timeout?.cancel()
        timeout = nil
        let waiters = fixWaiters
        fixWaiters = []
        for waiter in waiters { waiter.resume(with: result) }
    }

    private func authorizationChanged() {
        let current = access()
        // The delegate hears the current status as soon as it is set; only an answer ends the wait.
        guard current != .notDetermined, !accessWaiters.isEmpty else { return }
        let waiters = accessWaiters
        accessWaiters = []
        for waiter in waiters { waiter.resume(returning: current) }
    }
}

extension CoreLocationSource: CLLocationManagerDelegate {
    // The manager was made on the main thread, so its delegate is called there.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { authorizationChanged() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        MainActor.assumeIsolated { finishFix(.success(last)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as? CLError)?.code.rawValue ?? -1
        MainActor.assumeIsolated { finishFix(.failure(NoFix(reason: "Core Location error \(code)"))) }
    }
}
