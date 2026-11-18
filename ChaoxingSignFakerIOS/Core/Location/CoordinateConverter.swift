import CoreLocation
import Foundation

enum CoordinateConverter {
    private static let semiMajorAxis = 6_378_245.0
    private static let eccentricitySquared = 0.006693421622965943
    private static let xPi = Double.pi * 3_000.0 / 180.0

    static func wgs84ToBD09(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInChina(coordinate) else { return coordinate }
        return gcj02ToBD09(wgs84ToGCJ02(coordinate))
    }

    static func gcj02ToBD09(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInChina(coordinate) else { return coordinate }
        let x = coordinate.longitude
        let y = coordinate.latitude
        let z = sqrt(x * x + y * y) + 0.00002 * sin(y * xPi)
        let theta = atan2(y, x) + 0.000003 * cos(x * xPi)
        return CLLocationCoordinate2D(
            latitude: z * sin(theta) + 0.006,
            longitude: z * cos(theta) + 0.0065
        )
    }

    static func bd09ToWGS84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        gcj02ToWGS84(bd09ToGCJ02(coordinate))
    }

    static func bd09ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isInChina(coordinate) else { return coordinate }
        let x = coordinate.longitude - 0.0065
        let y = coordinate.latitude - 0.006
        let z = sqrt(x * x + y * y) - 0.00002 * sin(y * xPi)
        let theta = atan2(y, x) - 0.000003 * cos(x * xPi)
        return CLLocationCoordinate2D(
            latitude: z * sin(theta),
            longitude: z * cos(theta)
        )
    }

    /// Core Location GPS coordinates -> mainland map coordinates.
    static func wgs84ToGCJ02(
        _ coordinate: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        guard isInChina(coordinate) else { return coordinate }
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        var latitudeDelta = transformLatitude(longitude - 105.0, latitude - 35.0)
        var longitudeDelta = transformLongitude(longitude - 105.0, latitude - 35.0)
        let radianLatitude = latitude / 180.0 * Double.pi
        var magic = sin(radianLatitude)
        magic = 1.0 - eccentricitySquared * magic * magic
        let squareRootMagic = sqrt(magic)
        latitudeDelta = latitudeDelta * 180.0 /
            ((semiMajorAxis * (1.0 - eccentricitySquared)) /
                (magic * squareRootMagic) * Double.pi)
        longitudeDelta = longitudeDelta * 180.0 /
            (semiMajorAxis / squareRootMagic * cos(radianLatitude) * Double.pi)
        return CLLocationCoordinate2D(
            latitude: latitude + latitudeDelta,
            longitude: longitude + longitudeDelta
        )
    }

    /// Mainland map coordinates -> Core Location GPS coordinates.
    static func gcj02ToWGS84(
        _ coordinate: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        var estimate = coordinate
        for _ in 0..<4 {
            let converted = wgs84ToGCJ02(estimate)
            estimate.latitude += coordinate.latitude - converted.latitude
            estimate.longitude += coordinate.longitude - converted.longitude
        }
        return estimate
    }

    private static func transformLatitude(_ x: Double, _ y: Double) -> Double {
        var value = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y
            + 0.1 * x * y + 0.2 * sqrt(abs(x))
        value += (20.0 * sin(6.0 * x * Double.pi)
            + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        value += (20.0 * sin(y * Double.pi)
            + 40.0 * sin(y / 3.0 * Double.pi)) * 2.0 / 3.0
        value += (160.0 * sin(y / 12.0 * Double.pi)
            + 320.0 * sin(y * Double.pi / 30.0)) * 2.0 / 3.0
        return value
    }

    private static func transformLongitude(_ x: Double, _ y: Double) -> Double {
        var value = 300.0 + x + 2.0 * y + 0.1 * x * x
            + 0.1 * x * y + 0.1 * sqrt(abs(x))
        value += (20.0 * sin(6.0 * x * Double.pi)
            + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        value += (20.0 * sin(x * Double.pi)
            + 40.0 * sin(x / 3.0 * Double.pi)) * 2.0 / 3.0
        value += (150.0 * sin(x / 12.0 * Double.pi)
            + 300.0 * sin(x / 30.0 * Double.pi)) * 2.0 / 3.0
        return value
    }

    private static func isInChina(_ coordinate: CLLocationCoordinate2D) -> Bool {
        (0.8293...55.8271).contains(coordinate.latitude)
            && (72.004...137.8347).contains(coordinate.longitude)
    }
}

/// MapKit's mainland (高德) map and Core Location do not share a coordinate datum.
/// Keep this boundary explicit; CLLocationCoordinate2D itself carries no datum tag.
enum MapCoordinateSystem: String {
    case gcj02
    case wgs84

    func toWGS84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        switch self {
        case .gcj02: CoordinateConverter.gcj02ToWGS84(coordinate)
        case .wgs84: coordinate
        }
    }

    func fromWGS84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        switch self {
        case .gcj02: CoordinateConverter.wgs84ToGCJ02(coordinate)
        case .wgs84: coordinate
        }
    }
}
