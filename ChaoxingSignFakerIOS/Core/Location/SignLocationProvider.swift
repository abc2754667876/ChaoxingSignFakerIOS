import CoreLocation
import Observation

enum CurrentLocationError: LocalizedError {
    case permissionDenied
    case restricted
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "未获得位置权限，请在系统设置中允许此 App 使用当前位置"
        case .restricted:
            "当前设备限制了位置服务"
        case .unavailable:
            "暂时无法获取当前位置，请稍后重试"
        }
    }
}

@MainActor
@Observable
final class CurrentLocationProvider: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestCurrentLocation() async throws -> CLLocation {
        guard continuation == nil else { throw CurrentLocationError.unavailable }
        guard CLLocationManager.locationServicesEnabled() else {
            throw CurrentLocationError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied:
                finish(with: .failure(CurrentLocationError.permissionDenied))
            case .restricted:
                finish(with: .failure(CurrentLocationError.restricted))
            @unknown default:
                finish(with: .failure(CurrentLocationError.unavailable))
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied:
            finish(with: .failure(CurrentLocationError.permissionDenied))
        case .restricted:
            finish(with: .failure(CurrentLocationError.restricted))
        case .notDetermined:
            break
        @unknown default:
            finish(with: .failure(CurrentLocationError.unavailable))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(with: .failure(CurrentLocationError.unavailable))
            return
        }
        finish(with: .success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: .failure(error))
    }

    private func finish(with result: Result<CLLocation, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }
}

enum SignLocationResolver {
    static func resolve(_ location: CLLocation) async -> ChaoxingSignLocation {
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let address = placemark.map(address) ?? coordinateDescription(location.coordinate)
        return ChaoxingSignLocation(
            address: address,
            wgs84Coordinate: location.coordinate
        )
    }

    private static func address(for placemark: CLPlacemark) -> String {
        let components = [
            placemark.administrativeArea,
            placemark.locality,
            placemark.subLocality,
            placemark.thoroughfare,
            placemark.subThoroughfare
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

        var uniqueComponents: [String] = []
        for component in components where !uniqueComponents.contains(component) {
            uniqueComponents.append(component)
        }
        return uniqueComponents.isEmpty ? placemark.name ?? "未知地址" : uniqueComponents.joined()
    }

    private static func coordinateDescription(_ coordinate: CLLocationCoordinate2D) -> String {
        let latitude = coordinate.latitude.formatted(.number.precision(.fractionLength(6)))
        let longitude = coordinate.longitude.formatted(.number.precision(.fractionLength(6)))
        return "纬度 \(latitude)，经度 \(longitude)"
    }
}
