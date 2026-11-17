import Foundation

struct SavedLocation: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var address: String
    var name: String
    let latitude: Double
    let longitude: Double

    init(
        id: UUID = UUID(),
        address: String,
        name: String,
        latitude: Double,
        longitude: Double
    ) {
        self.id = id
        self.address = address
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
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
        return (try? JSONDecoder().decode([SavedLocation].self, from: data)) ?? []
    }

    func save(_ locations: [SavedLocation]) {
        guard let data = try? JSONEncoder().encode(locations) else { return }
        defaults.set(data, forKey: key)
    }
}
