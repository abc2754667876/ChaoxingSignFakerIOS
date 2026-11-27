import CoreLocation
import Testing
@testable import ChaoxingSignFakerIOS

struct CoordinateConverterTests {
    @Test(arguments: [0.0, 39.0, 80.0, -80.0])
    func randomizesSavedSubmissionWithinSevenMeters(_ latitude: Double) {
        let favorite = SavedLocation(
            address: "收藏地址", name: "收藏位置", latitude: latitude, longitude: 120
        )
        let original = favorite.signLocation
        let origin = CLLocation(latitude: original.bd09Latitude, longitude: original.bd09Longitude)
        var previous = original
        for _ in 0..<128 {
            let submission = original.randomizedWithinSevenMeters()
            let shifted = CLLocation(latitude: submission.bd09Latitude, longitude: submission.bd09Longitude)
            #expect(origin.distance(from: shifted) <= 7)
            #expect(submission.address == original.address)
            #expect(submission != previous)
            previous = submission
        }
        #expect(favorite.signLocation == original)
    }

    private let buildingWGS84 = CLLocationCoordinate2D(
        latitude: 39.06276057041804,
        longitude: 117.12602571810434
    )

    @Test func convertsGPSCoordinatesToMainlandMapCoordinates() {
        let coordinate = CoordinateConverter.wgs84ToGCJ02(buildingWGS84)

        #expect(abs(coordinate.latitude - 39.06387820835183) < 0.000001)
        #expect(abs(coordinate.longitude - 117.13244186712689) < 0.000001)
    }

    @Test func convertsLegacyBD09DirectlyToGCJ02() {
        let legacyBD09 = CLLocationCoordinate2D(
            latitude: 39.070157359566196,
            longitude: 117.13884421617868
        )

        let coordinate = CoordinateConverter.bd09ToGCJ02(legacyBD09)

        #expect(abs(coordinate.latitude - 39.06387820835183) < 0.000001)
        #expect(abs(coordinate.longitude - 117.13244186712689) < 0.000001)
    }

    @Test func roundTripsWGS84AndBD09() {
        let bd09 = CoordinateConverter.wgs84ToBD09(buildingWGS84)
        let roundTripped = CoordinateConverter.bd09ToWGS84(bd09)

        #expect(abs(roundTripped.latitude - buildingWGS84.latitude) < 0.000001)
        #expect(abs(roundTripped.longitude - buildingWGS84.longitude) < 0.000001)
    }

    @Test func leavesCoordinatesOutsideChinaUnchanged() {
        let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)

        let coordinate = CoordinateConverter.wgs84ToGCJ02(london)

        #expect(coordinate.latitude == london.latitude)
        #expect(coordinate.longitude == london.longitude)
    }

    @Test func mainlandMapTapAndGPSFixSubmitTheSameBD09Location() {
        // The historical fixture was a MapKit tap, incorrectly named WGS84 before.
        let gps = MapCoordinateSystem.gcj02.toWGS84(buildingWGS84)
        let favorite = SavedLocation(
            address: "测试地址", name: "地图选点",
            latitude: gps.latitude, longitude: gps.longitude
        )
        let fromGPS = ChaoxingSignLocation(address: "测试地址", wgs84Coordinate: gps)
        #expect(favorite.signLocation == fromGPS)
        #expect(fromGPS.bd09Latitude == 39.069094)
        #expect(fromGPS.bd09Longitude == 117.132412)
        let mapPoint = MapCoordinateSystem.gcj02.fromWGS84(favorite.wgs84Coordinate)
        #expect(abs(mapPoint.latitude - buildingWGS84.latitude) < 0.000001)
        #expect(abs(mapPoint.longitude - buildingWGS84.longitude) < 0.000001)
    }

    @Test func previousGCJSubmissionReproducesSouthwardShiftOnBaiduMap() {
        let wrongSubmission = CoordinateConverter.wgs84ToGCJ02(buildingWGS84)
        let displayedAsGCJ = CoordinateConverter.bd09ToGCJ02(wrongSubmission)
        let northMeters = (displayedAsGCJ.latitude - buildingWGS84.latitude) * 111_320
        let eastMeters = (displayedAsGCJ.longitude - buildingWGS84.longitude)
            * 111_320 * cos(buildingWGS84.latitude * .pi / 180)
        #expect(northMeters < -500)
        #expect(abs(eastMeters) < 50)
    }

    @Test func internationalMapModeDoesNotApplyMainlandMapShift() {
        let gps = MapCoordinateSystem.wgs84.toWGS84(buildingWGS84)
        #expect(gps.latitude == buildingWGS84.latitude)
        #expect(gps.longitude == buildingWGS84.longitude)
    }
}
