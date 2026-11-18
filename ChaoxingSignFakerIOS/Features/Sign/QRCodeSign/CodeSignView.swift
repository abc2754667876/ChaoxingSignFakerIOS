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
    @State private var locations: [SavedLocation] = []
    @State private var locationProvider = CurrentLocationProvider()
    private let store = SavedLocationStore()

    private var title: String { mode == .password ? "签到码签到" : "二维码签到" }
    private var isBusy: Bool { [.loading, .checking, .locating, .signing].contains(state) }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .foregroundStyle(state == .success || state == .alreadySigned ? .green : .accentColor)
                Text(title).font(.largeTitle)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if isPrepared && state == .ready && mode == .password {
                    TextField("请输入签到码", text: $password)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .multilineTextAlignment(.center)
                        .font(.title2.monospacedDigit())
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: password) { _, value in
                            password = String(value.filter(\.isNumber).prefix(codeLength.flatMap { $0 > 0 ? $0 : nil } ?? 16))
                        }
                }

                controls.padding(.top, 28)
            }
            .padding(24)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
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
            NavigationStack {
                List {
                    Button("使用当前位置") {
                        isShowingLocations = false
                        Task { await signUsingCurrentLocation() }
                    }
                    if locations.isEmpty {
                        Text("暂无收藏位置，可在“位置”页面添加。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(locations) { location in
                            Button {
                                isShowingLocations = false
                                Task { await sign(location.signLocation) }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(location.name)
                                    Text(location.address).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("选择签到位置")
                .toolbar { Button("取消") { isShowingLocations = false } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder private var controls: some View {
        if isBusy {
            ProgressView().controlSize(.large)
        } else if !isPrepared {
            Button("重新检查") { Task { await prepare() } }
                .buttonStyle(.borderedProminent)
        } else if state == .ready || state.isFailure {
            VStack(spacing: 12) {
                if mode == .password {
                    Button("验证并签到") { Task { await handlePassword() } }
                        .disabled(password.isEmpty || (codeLength.flatMap { $0 > 0 ? $0 : nil }.map { password.count != $0 } ?? false))
                        .buttonStyle(.borderedProminent)
                } else {
                    Button(qrCode == nil ? "扫描二维码" : "重新扫描二维码") {
                        isShowingScanner = true
                    }
                    .buttonStyle(.borderedProminent)
                    if qrCode != nil {
                        Button("继续签到") { Task { await proceed() } }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var icon: String {
        switch state {
        case .success, .alreadySigned: "checkmark.circle.fill"
        case .expired: "clock.badge.xmark"
        case .failure: "exclamationmark.triangle.fill"
        default: mode == .password ? "number.square" : "qrcode.viewfinder"
        }
    }

    private var message: String {
        switch state {
        case .loading: return "正在检查活动状态与签到要求…"
        case .ready:
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
            case .alreadySigned: state = .alreadySigned
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
        state = .signing
        do {
            _ = try await model.signCode(activity, code: mode == .password ? password : nil, qrCode: qrCode, location: location)
            state = .success
        } catch let error as ChaoxingError {
            switch error {
            case .alreadySigned: state = .alreadySigned
            case .signExpired: state = .expired
            default: state = .failure(error.localizedDescription)
            }
        } catch { state = .failure(error.localizedDescription) }
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
