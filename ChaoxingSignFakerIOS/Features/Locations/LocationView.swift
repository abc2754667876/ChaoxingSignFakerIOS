//
//  LocationView.swift
//  ChaoxingSignFakerIOS
//
//  Created by Chengzhi 张 on 2026/11/17.
//

import CoreLocation
import MapKit
import Observation
import SwiftUI

struct LocationView: View {
    private let store: SavedLocationStore
    @AppStorage("mapCoordinateSystem") private var mapCoordinateSystem = MapCoordinateSystem.gcj02

    @State private var locations: [SavedLocation]
    @State private var showSheet = true
    @State private var searchText = ""
    @State private var detent: PresentationDetent = .fraction(0.45)
    @State private var position: MapCameraPosition = .userLocation(
        followsHeading: false,
        fallback: .automatic
    )
    @State private var displayStyle = MapDisplayStyle.standard
    @State private var pendingLocation: SavedLocation?
    @State private var editingLocation: SavedLocation?
    @State private var editedName = ""
    @State private var locationToDelete: SavedLocation?
    @State private var isResolvingAddress = false
    @State private var permissionManager = LocationPermissionManager()

    init(store: SavedLocationStore = SavedLocationStore()) {
        self.store = store
        _locations = State(initialValue: store.load())
    }

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()

                    ForEach(locations) { location in
                        Marker(
                            location.name,
                            systemImage: "star.fill",
                            coordinate: mapCoordinateSystem.fromWGS84(location.wgs84Coordinate)
                        )
                        .tint(.orange)
                    }
                }
                .mapStyle(displayStyle.mapStyle)
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                }
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            guard let coordinate = proxy.convert(value.location, from: .local) else {
                                return
                            }
                            prepareLocation(at: coordinate)
                        }
                )
            }
            .ignoresSafeArea(edges: .bottom)
            .overlay {
                if isResolvingAddress {
                    ProgressView("正在获取地址…")
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule())
                }
            }
            .sheet(isPresented: $showSheet) {
                favoritesSheet
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
            .navigationTitle("位置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSheet.toggle()
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel(showSheet ? "隐藏收藏列表" : "显示收藏列表")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("地图样式", selection: $displayStyle) {
                            ForEach(MapDisplayStyle.allCases) { style in
                                Label(style.title, systemImage: style.systemImage)
                                    .tag(style)
                            }
                        }
                        Picker("底图坐标模式", selection: $mapCoordinateSystem) {
                            ForEach(MapCoordinateSystem.allCases) { system in
                                Text(system.title).tag(system)
                            }
                        }
                    } label: {
                        Image(systemName: displayStyle.systemImage)
                    }
                    .accessibilityLabel("切换地图样式")
                }
            }
            .alert(
                "收藏此位置？",
                isPresented: isPresentingPendingLocation,
                presenting: pendingLocation
            ) { location in
                Button("收藏") {
                    locations.append(location)
                    persistLocations()
                }
                Button("取消", role: .cancel) {}
            } message: { location in
                Text("\(location.address)\nWGS-84 纬度：\(location.latitude.formattedCoordinate)  经度：\(location.longitude.formattedCoordinate)")
            }
            .onAppear {
                permissionManager.requestWhenInUseAuthorization()
            }
        }
    }

    private var favoritesSheet: some View {
        NavigationStack {
            Group {
                if filteredLocations.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "暂无收藏位置" : "未找到位置",
                        systemImage: searchText.isEmpty ? "mappin.slash" : "magnifyingglass",
                        description: Text(
                            searchText.isEmpty
                                ? "轻点地图上的任意位置即可收藏。"
                                : "请尝试搜索其他名称或地址。"
                        )
                    )
                } else {
                    List {
                        Section {
                            ForEach(filteredLocations) { location in
                                LocationItem(
                                    location: location,
                                    onSelect: { show(location) },
                                    onRename: { beginRenaming(location) },
                                    onDelete: { locationToDelete = location }
                                )
                            }
                        }
                        .listSectionSeparator(.hidden, edges: .top)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("收藏的位置")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "搜索名称或地址")
            .alert(
                "重命名位置",
                isPresented: isEditingLocation,
                presenting: editingLocation
            ) { location in
                TextField("收藏名称", text: $editedName)
                Button("保存") {
                    rename(location, to: editedName)
                }
                Button("取消", role: .cancel) {}
            } message: { location in
                Text(location.address)
            }
            .alert(
                "删除收藏位置？",
                isPresented: isDeletingLocation,
                presenting: locationToDelete
            ) { location in
                Button("删除", role: .destructive) {
                    delete(location)
                }
                Button("取消", role: .cancel) {}
            } message: { location in
                Text("“\(location.name)”将从收藏中移除，此操作无法撤销。")
            }
        }
    }

    private var filteredLocations: [SavedLocation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return locations }
        return locations.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.address.localizedCaseInsensitiveContains(query)
        }
    }

    private var isPresentingPendingLocation: Binding<Bool> {
        Binding(
            get: { pendingLocation != nil },
            set: { if !$0 { pendingLocation = nil } }
        )
    }

    private var isEditingLocation: Binding<Bool> {
        Binding(
            get: { editingLocation != nil },
            set: { if !$0 { editingLocation = nil } }
        )
    }

    private var isDeletingLocation: Binding<Bool> {
        Binding(
            get: { locationToDelete != nil },
            set: { if !$0 { locationToDelete = nil } }
        )
    }

    private func prepareLocation(at coordinate: CLLocationCoordinate2D) {
        let coordinate = mapCoordinateSystem.toWGS84(coordinate)
        showSheet = false
        isResolvingAddress = true

        Task {
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            ).first
            let address = placemark.map(Self.address) ?? Self.coordinateDescription(coordinate)
            let name = placemark?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingLocation = SavedLocation(
                address: address,
                name: name?.isEmpty == false ? name! : "收藏位置",
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                coordinateSystem: .wgs84
            )
            isResolvingAddress = false
        }
    }

    private func show(_ location: SavedLocation) {
        position = .region(
            MKCoordinateRegion(
                center: mapCoordinateSystem.fromWGS84(location.wgs84Coordinate),
                span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006)
            )
        )
        showSheet = false
    }

    private func beginRenaming(_ location: SavedLocation) {
        editedName = location.name
        editingLocation = location
    }

    private func rename(_ location: SavedLocation, to newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = locations.firstIndex(where: { $0.id == location.id }) else {
            return
        }
        locations[index].name = trimmedName
        persistLocations()
    }

    private func delete(_ location: SavedLocation) {
        locations.removeAll { $0.id == location.id }
        persistLocations()
    }

    private func persistLocations() {
        store.save(locations)
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
        "纬度 \(coordinate.latitude.formattedCoordinate)，经度 \(coordinate.longitude.formattedCoordinate)"
    }
}

private struct LocationItem: View {
    let location: SavedLocation
    let onSelect: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
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
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)

            Button(action: onRename) {
                Image(systemName: "pencil.line")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重命名\(location.name)")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除\(location.name)")
        }
        .padding(.vertical, 4)
    }
}

private enum MapDisplayStyle: String, CaseIterable, Identifiable {
    case standard
    case imagery
    case hybrid

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "标准"
        case .imagery: "卫星"
        case .hybrid: "混合"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: "map"
        case .imagery: "globe.asia.australia.fill"
        case .hybrid: "square.3.layers.3d"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard
        case .imagery: .imagery
        case .hybrid: .hybrid
        }
    }
}

@MainActor
@Observable
private final class LocationPermissionManager: NSObject, CLLocationManagerDelegate {
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestWhenInUseAuthorization() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }
}

private extension Double {
    var formattedCoordinate: String {
        formatted(.number.precision(.fractionLength(6)))
    }
}

#Preview {
    LocationView()
}
