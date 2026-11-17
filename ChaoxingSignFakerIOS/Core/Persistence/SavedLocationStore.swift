import CoreLocation
import Foundation

enum SavedLocationCoordinateSystem: String, Codable, Sendable {
    case wgs84
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
        coordinateSystem: SavedLocationCoordinateSystem = .bd09
    ) {
        self.id = id
        self.address = address
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.coordinateSystem = coordinateSystem
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
    private let key = "savedLocations.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [SavedLocation] {
        guard let data = defaults.data(forKey: key) else { return [] }
        guard let locations = try? JSONDecoder().decode([SavedLocation].self, from: data) else {
            return []
        }
        var didMigrate = false
        let migratedLocations = locations.map { location in
            guard location.coordinateSystem == .wgs84 else { return location }
            didMigrate = true
            let coordinate = CoordinateConverter.wgs84ToBD09(
                .init(latitude: location.latitude, longitude: location.longitude)
            )
            return SavedLocation(
                id: location.id,
                address: location.address,
                name: location.name,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                coordinateSystem: .bd09
            )
        }
        if didMigrate {
            save(migratedLocations)
        }
        return migratedLocations
    }

    func save(_ locations: [SavedLocation]) {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        defaults.set(data, forKey: key)
    }
}
