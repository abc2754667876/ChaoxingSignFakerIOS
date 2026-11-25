import AVFoundation
import SwiftUI

struct CodeSignView: View {
    enum Mode { case password, qrCode }
    fileprivate enum State: Equatable {
        case loading, ready, checking, locating, signing, success, alreadySigned, expired
        case failure(String)
    }

    let model: AppModel
    let activity: ChaoxingActivity
    let mode: Mode

    @State private var state: State = .loading
    @State private var isPrepared = false
    @State private var isLocationRequired = false
    @State private var codeLength: Int?
    @State private var isRefreshingQR = false
    @State private var password = ""
    @State private var qrCode: ParsedSignQRCode?
    @State private var isShowingScanner = false
    @State private var isShowingLocations = false
    @State private var locationSelection = 0
    @State private var detent: PresentationDetent = .fraction(0.45)
    @State private var locations: [SavedLocation] = []
    @State private var locationProvider = CurrentLocationProvider()
    private let store = SavedLocationStore()
    @State private var multi = MultiAccountSign()

    private var title: String { mode == .password ? "签到码签到" : "二维码签到" }
    private var isBusy: Bool { [.loading, .checking, .locating, .signing].contains(state) }
    private var color: Color {
        switch state {
        case .success, .alreadySigned: .green
        case .expired, .failure: .orange
        default: .accentColor
        }
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

                    Text(title)
                        .font(.largeTitle)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(state.isFailure ? .orange : .secondary)
                        .multilineTextAlignment(.center)

                    if isPrepared && (state == .ready || state.isFailure || (state == .success && !multi.pendingIDs(current: model.user).isEmpty)) && mode == .password {
                        TextField("请输入签到码", text: $password)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .multilineTextAlignment(.center)
                            .font(.title2.monospacedDigit())
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 320)
                            .padding(.top, 24)
                            .onChange(of: password) { _, value in
                                password = String(value.filter(\.isNumber).prefix(codeLength.flatMap { $0 > 0 ? $0 : nil } ?? 16))
                            }
                    }

                    controls
                        .padding(.top, isPrepared && mode == .password ? 20 : 72)
                }
                .padding(.horizontal)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { MultiAccountToolbar(model: model, multi: multi) } }
        .sheet(isPresented: $multi.isShowing) { MultiAccountChooser(model: model, multi: multi) }
        .sheet(isPresented: $isShowingScanner) {
            NavigationStack {
                SignQRScanner { raw in
                    isShowingScanner = false
                    Task { await handleQR(raw) }
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("扫描签到二维码")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("取消") { isShowingScanner = false } }
            }
        }
        .sheet(isPresented: $isShowingLocations) {
            locationsSheet
                .presentationDetents([.fraction(0.45), .large], selection: $detent)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(36)
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
        }
        .animation(.default, value: state)
    }

    @ViewBuilder
    private var controls: some View {
        if isBusy {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 48)
        } else if !isPrepared {
            if state.isFailure {
                actionButton("重新检查", systemImage: "arrow.clockwise", color: .orange) {
                    Task { await prepare() }
                }
            } else {
                actionLabel(buttonTitle, systemImage: icon, color: color)
            }
        } else if state == .ready || state.isFailure || (state == .success && !multi.pendingIDs(current: model.user).isEmpty) {
            VStack(spacing: 12) {
                if mode == .password {
                    actionButton("验证并签到", systemImage: activity.kind.systemImage, color: color) {
                        Task { await handlePassword() }
                    }
                        .disabled(password.isEmpty || (codeLength.flatMap { $0 > 0 ? $0 : nil }.map { password.count != $0 } ?? false))
                } else {
                    actionButton(qrCode == nil ? "扫描二维码" : "重新扫描二维码", systemImage: activity.kind.systemImage, color: color) {
                        isShowingScanner = true
                    }
                    if qrCode != nil {
                        actionButton("继续签到", systemImage: "arrow.clockwise", color: .secondary) {
                            Task { await proceed() }
                        }
                    }
                }
            }
            .disabled(multi.pendingIDs(current: model.user).isEmpty)
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
                        Text("将获取设备当前位置与地址，并随签到凭证一起提交")
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
                                Text(location.name).font(.headline)
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
            .navigationTitle("选择签到位置")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func actionButton(_ text: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
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

    private var buttonTitle: String {
        switch state {
        case .success, .alreadySigned: "已签到"
        case .expired: "签到已截止"
        default: ""
        }
    }

    private var icon: String {
        switch state {
        case .success, .alreadySigned: "checkmark.circle.fill"
        case .expired: "clock.badge.xmark"
        case .failure: "exclamationmark.triangle.fill"
        case .loading, .checking, .locating, .signing: "hourglass"
        case .ready: activity.kind.systemImage
        }
    }

    private var message: String {
        switch state {
        case .loading: return "正在检查活动状态与签到要求…"
        case .ready:
            if multi.isCurrentAlreadySigned(model.user) {
                return "当前账号已签到，可选择其他账号签到"
            }
            if mode == .password {
                return "请输入教师设置的\(codeLength.flatMap { $0 > 0 ? String($0) : nil } ?? "")位签到码\(isLocationRequired ? "，验证后选择位置" : "")"
            }
            return "扫描教师展示的二维码\(isRefreshingQR ? "，动态二维码过期后需重新扫描" : "")\(isLocationRequired ? "，然后选择位置" : "")"
        case .checking: return "正在验证签到凭证…"
        case .locating: return "正在获取当前位置与地址…"
        case .signing: return "正在提交签到…"
        case .success: return "签到成功"
        case .alreadySigned: return "你已经签到过了"
        case .expired: return "签到已截止"
        case .failure(let message): return message
        }
    }

    private func prepare() async {
        multi.load(current: model.user)
        isPrepared = false
        state = .loading
        do {
            switch try await model.prepareCodeSign(activity) {
            case .ready(let locationRequired, let length, let refreshing):
                isLocationRequired = locationRequired
                codeLength = length
                isRefreshingQR = refreshing
                isPrepared = true
                state = .ready
            case .alreadySigned(let locationRequired, let length, let refreshing):
                isLocationRequired = locationRequired
                codeLength = length
                isRefreshingQR = refreshing
                isPrepared = true
                multi.markCurrent(model.user, as: .alreadySigned)
                state = .ready
            case .expired: state = .expired
            }
        } catch { state = .failure(error.localizedDescription) }
    }

    private func handlePassword() async {
        state = .checking
        do {
            guard try await model.checkPassword(password, for: activity) else {
                state = .failure("签到码错误，请重新输入")
                return
            }
            await proceed()
        } catch { state = .failure(error.localizedDescription) }
    }

    private func handleQR(_ raw: String) async {
        state = .checking
        qrCode = nil
        do {
            let parsed = try ParsedSignQRCode(raw)
            guard try await model.checkQRCode(parsed, for: activity) else {
                state = .failure("二维码已过期，请重新扫描")
                return
            }
            qrCode = parsed
            await proceed()
        } catch ChaoxingError.signExpired {
            state = .expired
        } catch { state = .failure(error.localizedDescription) }
    }

    private func proceed() async {
        if isLocationRequired {
            locations = store.load()
            state = .ready
            isShowingLocations = true
        } else {
            await sign(nil)
        }
    }

    private func signUsingCurrentLocation() async {
        state = .locating
        do {
            let current = try await locationProvider.requestCurrentLocation()
            await sign(await SignLocationResolver.resolve(current))
        } catch { state = .failure(error.localizedDescription) }
    }

    private func sign(_ location: ChaoxingSignLocation?) async {
        guard !multi.pendingIDs(current: model.user).isEmpty else { state = .ready; return }
        state = .signing
        let code = mode == .password ? password : nil
        let scanned = qrCode
        let failed = await multi.sign(model: model) {
            try await model.signForCurrent { api in
                _ = try await api.signCode(activity, code: code, qrCode: scanned, location: location)
                return .success
            }
        } other: { api in
            switch try await api.prepareCodeSign(activity) {
            case .ready:
                if let code {
                    guard try await api.checkPassword(code, for: activity) else {
                        throw ChaoxingError.invalidInput("签到码错误")
                    }
                }
                _ = try await api.signCode(activity, code: code, qrCode: scanned, location: location)
                return .success
            case .alreadySigned: return .alreadySigned
            case .expired: return .expired
            }
        }
        state = failed ? .failure("部分账号签到失败，可重试") : .success
    }
}

private extension CodeSignView.State {
    var isFailure: Bool { if case .failure = self { true } else { false } }
}

private struct SignQRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

private final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var didScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        Task { @MainActor in
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                let label = UILabel()
                label.text = "请在系统设置中允许相机权限后重试"
                label.textColor = .white
                label.textAlignment = .center
                label.frame = view.bounds
                label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.addSubview(label)
                return
            }
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer
            Task.detached { [session] in session.startRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Task.detached { [session] in session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didScan, let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        didScan = true
        onScan?(value)
    }
}
