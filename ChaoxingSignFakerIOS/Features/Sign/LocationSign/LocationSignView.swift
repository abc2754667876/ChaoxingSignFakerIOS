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
    @State private var multi = MultiAccountSign()

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

            FaceSignRequirementLabel(model: model, activity: activity)

            controls
                .padding(.top, 72)
        }
        .padding(.horizontal)
        .navigationTitle("位置签到")
        .navigationBarTitleDisplayMode(.inline)
        .signVerificationSupport(model: model, activity: activity)
        .task { await prepare() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { MultiAccountToolbar(model: model, multi: multi) } }
        .sheet(isPresented: $multi.isShowing) { MultiAccountChooser(model: model, multi: multi) }
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
            .disabled(multi.pendingIDs(current: model.user).isEmpty)
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
                                Task { await sign(location.signLocation, isSavedLocation: true) }
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
        case .ready: activity.kind.systemImage
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
        case .ready: multi.isCurrentAlreadySigned(model.user) ? "当前账号已签到，可选择其他账号签到" : readyMessage
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
        hasPrepared && (state == .ready || state.isFailure || (state == .success && !multi.pendingIDs(current: model.user).isEmpty))
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
        multi.load(current: model.user)
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
                multi.markCurrent(model.user, as: .alreadySigned)
                updateState(.ready)
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
            let signLocation = await SignLocationResolver.resolve(location)
            await sign(signLocation)
        } catch {
            updateState(.failure(error.localizedDescription))
        }
    }

    private func sign(_ location: ChaoxingSignLocation, isSavedLocation: Bool = false) async {
        guard !multi.pendingIDs(current: model.user).isEmpty else { updateState(.ready); return }
        updateState(.signing)
        let failed = await multi.sign(model: model) {
            let submission = isSavedLocation ? location.randomizedWithinSevenMeters() : location
            return try await model.signForCurrent { api in
                _ = try await api.signLocation(activity, location: submission)
                return .success
            }
        } other: { api in
            switch try await api.prepareLocationSign(activity) {
            case .ready:
                let submission = isSavedLocation ? location.randomizedWithinSevenMeters() : location
                _ = try await api.signLocation(activity, location: submission)
                return .success
            case .alreadySigned: return .alreadySigned
            case .expired: return .expired
            }
        }
        updateState(failed ? .failure("部分账号签到失败，可重试") : .success)
    }

}

private extension LocationSignView.State {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
