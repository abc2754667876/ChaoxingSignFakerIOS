import CoreLocation
import Foundation
import Testing
@testable import ChaoxingSignFakerIOS

struct SavedLocationStoreTests {
    @Test func repairsEachLegacyEncodingAndMigratesOnlyOnce() throws {
        let suite = "SavedLocationStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Same tap, encoded by the original app, the BD-09 patch, and the last fix.
        let legacyJSON = """
        [
          {"id":"A60CF254-B4CE-48DC-8081-1BD6EDEA25F2","name":"original","address":"原地址","latitude":39.06276057041804,"longitude":117.12602571810434},
          {"id":"A60CF254-B4CE-48DC-8081-1BD6EDEA25F3","name":"bd09 patch","address":"原地址","latitude":39.070157359566196,"longitude":117.13884421617868,"coordinateSystem":"bd09"},
          {"id":"A60CF254-B4CE-48DC-8081-1BD6EDEA25F4","name":"previous fix","address":"原地址","latitude":39.06276057041804,"longitude":117.12602571810434,"coordinateSystem":"wgs84"}
        ]
        """
        let original = Data(legacyJSON.utf8)
        defaults.set(original, forKey: "savedLocations.v1")
        let store = SavedLocationStore(defaults: defaults)
        let locations = store.load()
        #expect(locations.count == 3)
        for location in locations {
            #expect(location.coordinateSystem == .wgs84)
            #expect(location.address == "原地址")
            #expect(location.signLocation.bd09Latitude == 39.069094)
            #expect(location.signLocation.bd09Longitude == 117.132412)
            let mapPoint = MapCoordinateSystem.gcj02.fromWGS84(location.wgs84Coordinate)
            #expect(abs(mapPoint.latitude - 39.06276057041804) < 0.000001)
            #expect(abs(mapPoint.longitude - 117.12602571810434) < 0.000001)
        }
        #expect(locations.first?.id.uuidString == "A60CF254-B4CE-48DC-8081-1BD6EDEA25F2")
        #expect(defaults.data(forKey: "savedLocations.v1") == original)
        #expect(defaults.data(forKey: "savedLocations.v2") != nil)
        #expect(store.load() == locations)
        let persisted = defaults.data(forKey: "savedLocations.v2")
        #expect(store.load() == locations)
        #expect(defaults.data(forKey: "savedLocations.v2") == persisted)
    }

    @Test func preservesRealWGS84InV2WithoutApplyingLegacyRepair() throws {
        let suite = "SavedLocationStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let location = SavedLocation(
            address: "地址", name: "新收藏", latitude: 39.06276, longitude: 117.12602
        )
        let store = SavedLocationStore(defaults: defaults)
        store.save([location])
        #expect(store.load() == [location])
        #expect(store.load() == [location])
    }

    @Test func respectsInternationalMapModeWhenMigratingLegacyTap() throws {
        let suite = "SavedLocationStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("wgs84", forKey: "mapCoordinateSystem")
        let old = SavedLocation(address: "地址", name: "国际底图选点", latitude: 39.06, longitude: 117.12)
        defaults.set(try JSONEncoder().encode([old]), forKey: "savedLocations.v1")
        #expect(SavedLocationStore(defaults: defaults).load() == [old])
    }

    @Test func deletingAllFavoritesDoesNotResurrectLegacyBackup() throws {
        let suite = "SavedLocationStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = SavedLocation(address: "地址", name: "旧位置", latitude: 39, longitude: 117)
        defaults.set(try JSONEncoder().encode([old]), forKey: "savedLocations.v1")
        let store = SavedLocationStore(defaults: defaults)
        #expect(store.load().count == 1)
        store.save([])
        #expect(store.load().isEmpty)
        #expect(defaults.data(forKey: "savedLocations.v1") != nil)
    }
}
