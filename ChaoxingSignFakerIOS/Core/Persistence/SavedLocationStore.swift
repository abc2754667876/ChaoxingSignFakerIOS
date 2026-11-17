import CoreLocation
import Foundation

enum SavedLocationCoordinateSystem: String, Codable, Sendable {
    case wgs84
    case gcj02
    case bd09
}

struct SavedLocation: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var address: String
    var name: String
    let latitude: Double
    let longitude: Double
    let coordinateSystem: SavedLocationCoordinateSystem

    init(
        id: UUID = UUID(),
        address: String,
        name: String,
        latitude: Double,
        longitude: Double,
        coordinateSystem: SavedLocationCoordinateSystem = .wgs84
    ) {
        self.id = id
        self.address = address
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.coordinateSystem = coordinateSystem
    }

    /// Map display and persisted favorites use WGS-84 as their canonical representation.
    var wgs84Coordinate: CLLocationCoordinate2D {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return switch coordinateSystem {
        case .wgs84: coordinate
        case .gcj02: CoordinateConverter.gcj02ToWGS84(coordinate)
        case .bd09: CoordinateConverter.bd09ToWGS84(coordinate)
        }
    }

    /// Mainland map representation; this is not the Chaoxing submission datum.
    var gcj02Coordinate: CLLocationCoordinate2D {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return switch coordinateSystem {
        case .wgs84: CoordinateConverter.wgs84ToGCJ02(coordinate)
        case .gcj02: coordinate
        case .bd09: CoordinateConverter.bd09ToGCJ02(coordinate)
        }
    }

    var normalizedToWGS84: SavedLocation {
        guard coordinateSystem != .wgs84 else { return self }
        let coordinate = wgs84Coordinate
        return SavedLocation(
            id: id,
            address: address,
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            coordinateSystem: .wgs84
        )
    }

    var signLocation: ChaoxingSignLocation {
        ChaoxingSignLocation(address: address, wgs84Coordinate: wgs84Coordinate)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case address
        case name
        case latitude
        case longitude
        case coordinateSystem
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        address = try container.decode(String.self, forKey: .address)
        name = try container.decode(String.self, forKey: .name)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        coordinateSystem = try container.decodeIfPresent(
            SavedLocationCoordinateSystem.self,
            forKey: .coordinateSystem
        ) ?? .wgs84
    }
}

struct SavedLocationStore {
    private let defaults: UserDefaults
    private let key = "savedLocations.v2"
    private let legacyKey = "savedLocations.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [SavedLocation] {
        if defaults.data(forKey: key) == nil {
            return migrateLegacyMapCoordinates()
        }
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let locations = try? JSONDecoder().decode([SavedLocation].self, from: data) else {
            return []
        }
        let normalizedLocations = locations.map(\.normalizedToWGS84)
        if normalizedLocations != locations {
            save(normalizedLocations)
        }
        return normalizedLocations
    }

    func save(_ locations: [SavedLocation]) {
        guard let data = try? JSONEncoder().encode(locations.map(\.normalizedToWGS84)) else { return }
        defaults.set(data, forKey: key)
    }

    private func migrateLegacyMapCoordinates() -> [SavedLocation] {
        guard let data = defaults.data(forKey: legacyKey),
              let locations = try? JSONDecoder().decode([SavedLocation].self, from: data) else {
            return []
        }
        let mapSystem = MapCoordinateSystem(
            rawValue: defaults.string(forKey: "mapCoordinateSystem") ?? ""
        ) ?? .gcj02
        let migrated = locations.map { location in
            // v1 stored MapKit tap coordinates as "wgs84", or passed those numbers
            // through wgs84ToBD09 and labelled them "bd09". Undo that old transform
            // FIRST to recover the original tap, then normalize the actual map datum.
            // This also covers v1 data already rewritten by the previous GCJ-02 fix.
            let raw = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
            let mapCoordinate = location.coordinateSystem == .bd09
                ? CoordinateConverter.bd09ToWGS84(raw) : raw
            let coordinate = mapSystem.toWGS84(mapCoordinate)
            return SavedLocation(
                id: location.id, address: location.address, name: location.name,
                latitude: coordinate.latitude, longitude: coordinate.longitude,
                coordinateSystem: .wgs84
            )
        }
        // Leave the original v1 bytes untouched as a recovery copy. v2 is read from
        // now on, so this conversion cannot repeat on subsequent launches.
        save(migrated)
        return migrated
    }
}
