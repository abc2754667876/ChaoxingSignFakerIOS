import SwiftUI
import UIKit

struct GestureSignView: View {
    fileprivate enum State: Equatable {
        case loading
        case ready
        case checking
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
    @State private var isLocationRequired = false
    @State private var verifiedCode: String?
    @State private var patternError: String?
    @State private var patternResetID = 0
    @State private var locations: [SavedLocation]
    @State private var locationSelection = 0
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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .foregroundStyle(color)
                        .contentTransition(.symbolEffect(.replace))

                    Text("手势签到")
                        .font(.largeTitle)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(isWarning ? .orange : .secondary)
                        .multilineTextAlignment(.center)

                    if shouldShowPattern {
                        patternArea
                            .padding(.top, 24)
                    } else {
                        controls
                            .padding(.top, 72)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
        }
        .navigationTitle("手势签到")
        .navigationBarTitleDisplayMode(.inline)
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
                .interactiveDismissDisabled(isProcessing)
        }
        .animation(.default, value: state)
    }

    private var patternArea: some View {
        VStack(spacing: 16) {
            GesturePatternView(
                isEnabled: canDrawPattern,
                isInvalid: patternError != nil,
                resetID: patternResetID,
                onComplete: handlePattern
            )
            .frame(maxWidth: 320)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if state == .checking {
                    ZStack {
                        RoundedRectangle(cornerRadius: 28)
                            .fill(.ultraThinMaterial)
                        ProgressView("正在验证手势…")
                            .controlSize(.large)
                    }
                }
            }

            if let patternError {
                Label(patternError, systemImage: "exclamationmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            } else {
                Text("按住圆点并依次滑过图案，松手后会自动验证")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if isProcessing {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 48)
        } else if verifiedCode != nil, isLocationRequired, canRetry {
            VStack(spacing: 12) {
                actionButton(
                    state.isFailure ? "重新选择签到位置" : "选择签到位置",
                    systemImage: "location.fill",
                    color: state.isFailure ? .orange : .accentColor
                ) {
                    locations = store.load()
                    isShowingLocations = true
                }
                .disabled(multi.pendingIDs(current: model.user).isEmpty)

                actionButton("重新绘制手势", systemImage: "arrow.counterclockwise", color: .secondary) {
                    redrawPattern()
                }
            }
        } else if let verifiedCode, canRetry {
            VStack(spacing: 12) {
                actionButton("重新提交签到", systemImage: "arrow.clockwise", color: .orange) {
                    Task { await sign(code: verifiedCode, location: nil) }
                }
                .disabled(multi.pendingIDs(current: model.user).isEmpty)

                actionButton("重新绘制手势", systemImage: activity.kind.systemImage, color: .secondary) {
                    redrawPattern()
                }
            }
        } else if !hasPrepared, state.isFailure {
            actionButton("重新检查", systemImage: "arrow.clockwise", color: .orange) {
                Task { await prepare() }
            }
        } else {
            actionLabel(buttonTitle, systemImage: icon, color: color)
        }
    }

    private var locationsSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("位置来源", selection: $locationSelection) {
                    Text("当前位置").tag(0)
                    Text("已收藏位置").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if locationSelection == 0 {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "location.north")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .foregroundStyle(Color.accentColor)
                        Text("将获取设备当前位置与地址，并随手势码一起提交")
                            .font(.headline)
                            .multilineTextAlignment(.center)

                        actionButton("使用当前位置签到", systemImage: "location.fill", color: .accentColor) {
                            isShowingLocations = false
                            Task { await signUsingCurrentLocation() }
                        }
                        .padding(.top, 16)
                        Spacer()
                    }
                    .padding(.horizontal)
                } else if locations.isEmpty {
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
                                Task {
                                    guard let verifiedCode else { return }
                                    await sign(code: verifiedCode, location: location.signLocation)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("选择签到位置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var icon: String {
        return switch state {
        case .loading, .checking, .locating, .signing: "hourglass"
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
        if patternError != nil { return "手势验证未通过，请重新绘制" }
        return switch state {
        case .loading: "正在检查活动状态与签到要求…"
        case .ready:
            if multi.isCurrentAlreadySigned(model.user), verifiedCode == nil {
                "当前账号已签到，可选择其他账号签到"
            } else if verifiedCode != nil, isLocationRequired {
                "手势验证成功，请选择签到位置"
            } else {
                "在下方绘制教师设置的手势图案"
            }
        case .checking: "正在验证手势图案…"
        case .locating: "正在获取当前位置与地址…"
        case .signing: "正在提交手势签到…"
        case .success: "签到成功"
        case .alreadySigned: "你已经签到过了"
        case .expired: "签到已截止"
        case .failure(let message): message
        }
    }

    private var buttonTitle: String {
        switch state {
        case .success, .alreadySigned: "已签到"
        case .expired: "签到已截止"
        default: ""
        }
    }

    private var shouldShowPattern: Bool {
        hasPrepared && verifiedCode == nil && (state == .ready || state == .checking || state.isFailure || (state == .success && !multi.pendingIDs(current: model.user).isEmpty))
    }

    private var canDrawPattern: Bool {
        hasPrepared && verifiedCode == nil && !multi.pendingIDs(current: model.user).isEmpty && (state == .ready || state.isFailure || state == .success)
    }

    private var canRetry: Bool {
        state == .ready || state.isFailure || (state == .success && !multi.pendingIDs(current: model.user).isEmpty)
    }

    private var isProcessing: Bool {
        state == .loading || state == .checking || state == .locating || state == .signing
    }

    private var isWarning: Bool {
        patternError != nil || state.isFailure
    }

    private func actionButton(
        _ text: String,
        systemImage: String,
        color: Color,
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
        verifiedCode = nil
        patternError = nil
        patternResetID += 1
        updateState(.loading)
        do {
            switch try await model.prepareGestureSign(activity) {
            case .ready(let isLocationRequired):
                self.isLocationRequired = isLocationRequired
                hasPrepared = true
                updateState(.ready)
            case .alreadySigned(let isLocationRequired):
                self.isLocationRequired = isLocationRequired
                hasPrepared = true
                multi.markCurrent(model.user, as: .alreadySigned)
                updateState(.ready)
            case .expired(let isLocationRequired):
                self.isLocationRequired = isLocationRequired
                hasPrepared = true
                updateState(.expired)
            }
        } catch {
            updateState(.failure(error.localizedDescription))
        }
    }

    private func handlePattern(_ nodes: [Int]) {
        let code = nodes.map { String($0 + 1) }.joined()
        guard !code.isEmpty else { return }
        patternError = nil
        Task { await validate(code) }
    }

    private func validate(_ code: String) async {
        updateState(.checking)
        do {
            guard try await model.checkGestureSignCode(code, for: activity) else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                patternError = "手势图案错误，请重新绘制"
                patternResetID += 1
                updateState(.ready)
                return
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            verifiedCode = code
            updateState(.ready)
            if isLocationRequired {
                locations = store.load()
                isShowingLocations = true
            } else {
                await sign(code: code, location: nil)
            }
        } catch {
            patternResetID += 1
            updateState(.failure(error.localizedDescription))
        }
    }

    private func signUsingCurrentLocation() async {
        guard let verifiedCode else { return }
        updateState(.locating)
        do {
            let location = try await locationProvider.requestCurrentLocation()
            let signLocation = await SignLocationResolver.resolve(location)
            await sign(code: verifiedCode, location: signLocation)
        } catch {
            updateState(.failure(error.localizedDescription))
        }
    }

    private func sign(code: String, location: ChaoxingSignLocation?) async {
        guard !multi.pendingIDs(current: model.user).isEmpty else { updateState(.ready); return }
        updateState(.signing)
        let failed = await multi.sign(model: model) {
            try await model.signForCurrent { api in
                _ = try await api.signGesture(activity, code: code, location: location)
                return .success
            }
        } other: { api in
            switch try await api.prepareGestureSign(activity) {
            case .ready:
                guard try await api.checkGestureSignCode(code, for: activity) else {
                    throw ChaoxingError.invalidInput("手势图案错误")
                }
                _ = try await api.signGesture(activity, code: code, location: location)
                return .success
            case .alreadySigned: return .alreadySigned
            case .expired: return .expired
            }
        }
        updateState(failed ? .failure("部分账号签到失败，可重试") : .success)
    }

    private func redrawPattern() {
        verifiedCode = nil
        patternError = nil
        patternResetID += 1
        updateState(.ready)
    }
}

private extension GestureSignView.State {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

private struct GesturePatternView: View {
    let isEnabled: Bool
    let isInvalid: Bool
    let resetID: Int
    let onComplete: ([Int]) -> Void

    @State private var selectedNodes: [Int] = []
    @State private var currentPoint: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let points = nodePoints(in: geometry.size)
            Canvas { context, size in
                drawPattern(context: &context, size: size, points: points)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard isEnabled else { return }
                        currentPoint = value.location
                        guard let node = hitNode(at: value.location, points: points, size: geometry.size),
                              !selectedNodes.contains(node) else { return }
                        append(node)
                    }
                    .onEnded { _ in
                        guard isEnabled else { return }
                        currentPoint = nil
                        guard !selectedNodes.isEmpty else { return }
                        onComplete(selectedNodes)
                    }
            )
            .accessibilityLabel("九宫格手势输入")
            .accessibilityHint("按住并依次滑过圆点来绘制教师设置的签到图案")
        }
        .onChange(of: resetID) {
            selectedNodes = []
            currentPoint = nil
        }
    }

    private func drawPattern(
        context: inout GraphicsContext,
        size: CGSize,
        points: [CGPoint]
    ) {
        let selectedColor: Color = isInvalid ? .orange : .accentColor
        if let first = selectedNodes.first {
            var path = Path()
            path.move(to: points[first])
            for node in selectedNodes.dropFirst() {
                path.addLine(to: points[node])
            }
            if let currentPoint, isEnabled {
                path.addLine(to: currentPoint)
            }
            context.stroke(
                path,
                with: .color(selectedColor.opacity(0.8)),
                style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round)
            )
        }

        let diameter = min(size.width, size.height) * 0.13
        for (index, point) in points.enumerated() {
            let rect = CGRect(
                x: point.x - diameter / 2,
                y: point.y - diameter / 2,
                width: diameter,
                height: diameter
            )
            if selectedNodes.contains(index) {
                context.fill(Path(ellipseIn: rect), with: .color(selectedColor))
                let inner = rect.insetBy(dx: diameter * 0.32, dy: diameter * 0.32)
                context.fill(Path(ellipseIn: inner), with: .color(.white))
            } else {
                context.fill(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.24)))
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(.secondary.opacity(0.5)),
                    lineWidth: 2
                )
            }
        }
    }

    private func nodePoints(in size: CGSize) -> [CGPoint] {
        let side = min(size.width, size.height)
        let inset = side * 0.15
        let spacing = (side - inset * 2) / 2
        return (0..<9).map { index in
            CGPoint(
                x: (size.width - side) / 2 + inset + CGFloat(index % 3) * spacing,
                y: (size.height - side) / 2 + inset + CGFloat(index / 3) * spacing
            )
        }
    }

    private func hitNode(at location: CGPoint, points: [CGPoint], size: CGSize) -> Int? {
        let radius = min(size.width, size.height) * 0.115
        return points.indices.first { index in
            hypot(location.x - points[index].x, location.y - points[index].y) <= radius
        }
    }

    private func append(_ node: Int) {
        if let previous = selectedNodes.last,
           let middle = middleNode(from: previous, to: node),
           !selectedNodes.contains(middle) {
            selectedNodes.append(middle)
        }
        selectedNodes.append(node)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func middleNode(from start: Int, to end: Int) -> Int? {
        let startRow = start / 3
        let startColumn = start % 3
        let endRow = end / 3
        let endColumn = end % 3
        let rowDifference = abs(startRow - endRow)
        let columnDifference = abs(startColumn - endColumn)
        guard (rowDifference == 2 && columnDifference == 0)
                || (rowDifference == 0 && columnDifference == 2)
                || (rowDifference == 2 && columnDifference == 2) else {
            return nil
        }
        return ((startRow + endRow) / 2) * 3 + (startColumn + endColumn) / 2
    }
}
