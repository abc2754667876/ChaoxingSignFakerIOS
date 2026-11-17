import CoreLocation
import Observation
import SwiftUI

struct LocationSignView: View {
    fileprivate enum State: Equatable {
        case loading
        case ready
        case locating
        case signing
        case success
        case alreadySigned
        case expired
        case failure(String)
    }

    let model: AppModel
    let activity: ChaoxingActivity

    private let store: SavedLocationStore
    @State private var state: State = .loading
    @State private var hasPrepared = false
    @State private var detail: LocationSignDetail?
    @State private var locations: [SavedLocation]
    @State private var isShowingLocations = false
    @State private var detent: PresentationDetent = .fraction(0.45)
    @State private var locationProvider = CurrentLocationProvider()

    init(
        model: AppModel,
        activity: ChaoxingActivity,
        store: SavedLocationStore = SavedLocationStore()
    ) {
        self.model = model
        self.activity = activity
        self.store = store
        _locations = SwiftUI.State(initialValue: store.load())
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))

            Text("位置签到")
                .font(.largeTitle)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(state.isFailure ? .orange : .secondary)
                .multilineTextAlignment(.center)

            controls
                .padding(.top, 72)
        }
        .padding(.horizontal)
        .navigationTitle("位置签到")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .onAppear { locations = store.load() }
        .sheet(isPresented: $isShowingLocations) {
            locationsSheet
                .presentationDetents(
                    [.fraction(0.45), .large],
                    selection: $detent
                )
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(36)
                .presentationBackgroundInteraction(
                    .enabled(upThrough: .fraction(0.45))
                )
        }
        .animation(.default, value: state)
    }

    @ViewBuilder
    private var controls: some View {
        if isProcessing {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 48)
        } else if canChooseLocation {
            VStack(spacing: 12) {
                actionButton(
                    state.isFailure ? "重新使用当前位置签到" : "使用当前位置签到",
                    systemImage: "location.fill"
                ) {
                    Task { await signUsingCurrentLocation() }
                }

                actionButton("使用已收藏位置签到", systemImage: "star.fill") {
                    locations = store.load()
                    isShowingLocations = true
                }
            }
        } else if case .failure = state {
            actionButton("重新检查", systemImage: "arrow.clockwise") {
                Task { await prepare() }
            }
        } else {
            actionLabel(buttonTitle, systemImage: icon, color: color)
        }
    }

    private var locationsSheet: some View {
        NavigationStack {
            Group {
                if locations.isEmpty {
                    ContentUnavailableView(
                        "暂无收藏位置",
                        systemImage: "mappin.slash",
                        description: Text("请先在“位置”页面轻点地图收藏常用签到位置。")
                    )
                } else {
                    List(locations) { location in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(location.name)
                                    .font(.headline)
                                Text(location.address)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button("确认签到") {
                                isShowingLocations = false
                                Task { await sign(location.signLocation) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("使用收藏位置签到")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var icon: String {
        switch state {
        case .loading, .locating, .signing: "hourglass"
        case .ready: "location"
        case .success, .alreadySigned: "checkmark.circle.fill"
        case .expired: "clock.badge.xmark"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .success, .alreadySigned: .green
        case .expired, .failure: .orange
        default: .accentColor
        }
    }

    private var message: String {
        switch state {
        case .loading: "正在检查活动状态与签到要求…"
        case .ready: readyMessage
        case .locating: "正在获取当前位置与地址…"
        case .signing: "正在提交位置签到…"
        case .success: "签到成功"
        case .alreadySigned: "你已经签到过了"
        case .expired: "签到已截止"
        case .failure(let message): message
        }
    }

    private var readyMessage: String {
        if let range = detail?.range, range > 0 {
            return "使用当前位置或收藏位置签到，签到范围约为 \(range) 米"
        }
        return "使用当前位置或选择收藏的位置签到"
    }

    private var buttonTitle: String {
        switch state {
        case .success, .alreadySigned: "已签到"
        case .expired: "签到已截止"
        default: ""
        }
    }

    private var isProcessing: Bool {
        state == .loading || state == .locating || state == .signing
    }

    private var canChooseLocation: Bool {
        hasPrepared && (state == .ready || state.isFailure)
    }

    private func actionButton(
        _ text: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionLabel(text, systemImage: systemImage, color: color)
        }
        .buttonStyle(.plain)
    }

    private func actionLabel(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(color, in: Capsule())
    }

    private func updateState(_ newState: State) {
        withAnimation { state = newState }
    }

    private func prepare() async {
        hasPrepared = false
        updateState(.loading)
        do {
            switch try await model.prepareLocationSign(activity) {
            case .ready(let detail):
                self.detail = detail
                hasPrepared = true
                updateState(.ready)
            case .alreadySigned(let detail):
                self.detail = detail
                hasPrepared = true
                updateState(.alreadySigned)
            case .expired(let detail):
                self.detail = detail
                hasPrepared = true
                updateState(.expired)
            }
        } catch {
            updateState(.failure(error.localizedDescription))
        }
    }

    private func signUsingCurrentLocation() async {
        updateState(.locating)
        do {
            let location = try await locationProvider.requestCurrentLocation()
            let signLocation = await Self.signLocation(from: location)
            await sign(signLocation)
        } catch {
            updateState(.failure(error.localizedDescription))
        }
    }

    private func sign(_ location: ChaoxingSignLocation) async {
        updateState(.signing)
        do {
            _ = try await model.signLocation(activity, location: location)
            updateState(.success)
        } catch let error as ChaoxingError {
            switch error {
            case .alreadySigned: updateState(.alreadySigned)
            case .signExpired: updateState(.expired)
            default: updateState(.failure(error.localizedDescription))
            }
        } catch {
            updateState(.failure(error.localizedDescription))
        }
    }

    private static func signLocation(from location: CLLocation) async -> ChaoxingSignLocation {
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        let address = placemark.map(address) ?? coordinateDescription(location.coordinate)
        let coordinate = CoordinateConverter.wgs84ToBD09(location.coordinate)
        return ChaoxingSignLocation(
            address: address,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
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

private enum CurrentLocationError: LocalizedError {
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
private final class CurrentLocationProvider: NSObject, CLLocationManagerDelegate {
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

private extension SavedLocation {
    var signLocation: ChaoxingSignLocation {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let bd09Coordinate = switch coordinateSystem {
        case .wgs84: CoordinateConverter.wgs84ToBD09(coordinate)
        case .bd09: coordinate
        }
        return ChaoxingSignLocation(
            address: address,
            latitude: bd09Coordinate.latitude,
            longitude: bd09Coordinate.longitude
        )
    }
}

private extension LocationSignView.State {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
