import PhotosUI
import SwiftUI
import UIKit

struct PhotoSignView: View {
    fileprivate enum State: Equatable {
        case loading
        case ready
        case signing
        case success
        case alreadySigned
        case expired
        case failure(String)
    }

    let model: AppModel
    let activity: ChaoxingActivity

    @State private var state: State = .loading
    @State private var isPhotoRequired = true
    @State private var hasPrepared = false
    @State private var selectedImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var isShowingCameraUnavailable = false
    @State private var multi = MultiAccountSign()

    var body: some View {
        Group {
            if hasPrepared && !isPhotoRequired {
                OrdinarySignView(model: model, activity: activity)
            } else {
                photoContent
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .signVerificationSupport(model: model, activity: activity)
        .task { await prepare() }
        .toolbar { if !hasPrepared || isPhotoRequired { ToolbarItem(placement: .topBarTrailing) { MultiAccountToolbar(model: model, multi: multi) } } }
        .sheet(isPresented: $multi.isShowing) { MultiAccountChooser(model: model, multi: multi) }
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadAndSubmit(newItem) }
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker { image in
                isCameraPresented = false
                selectedImage = image
                Task { await submit(image) }
            } onCancel: {
                isCameraPresented = false
            }
            .ignoresSafeArea()
        }
        .alert("无法使用相机", isPresented: $isShowingCameraUnavailable) {
            Button("好") {}
        } message: {
            Text("当前设备不支持相机拍摄，请改从相册选择图片。")
        }
        .animation(.default, value: state)
    }

    private var photoContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
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

                    FaceSignRequirementLabel(model: model, activity: activity)

                    if let selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(.secondary.opacity(0.2))
                            }
                            .padding(.top, 12)
                    }

                    controls
                        .padding(.top, selectedImage == nil ? 72 : 20)
                }
                .padding(.horizontal)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if state == .loading || state == .signing {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 48)
        } else if canChoosePhoto {
            VStack(spacing: 12) {
                if let selectedImage, state.isFailure || state == .success {
                    actionButton(state.isFailure ? "重新提交当前图片" : "使用当前图片继续签到", systemImage: "arrow.clockwise", color: state.isFailure ? .orange : .accentColor) {
                        Task { await submit(selectedImage) }
                    }
                }

                actionButton("相机拍摄图片", systemImage: "camera.fill", color: .accentColor) {
                    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                        isShowingCameraUnavailable = true
                        return
                    }
                    isCameraPresented = true
                }

                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    actionLabel("相册选择图片", systemImage: "photo.on.rectangle", color: .accentColor)
                }
                .buttonStyle(.plain)
            }
            .disabled(multi.pendingIDs(current: model.user).isEmpty)
        } else if canSubmitOrdinary {
            actionButton(state.isFailure ? "重新签到" : "确认签到", systemImage: activity.kind.systemImage, color: color) {
                Task { await submitOrdinary() }
            }
        } else if case .failure = state {
            actionButton("重新检查", systemImage: "arrow.clockwise", color: .orange) {
                Task { await prepare() }
            }
        } else {
            actionLabel(buttonTitle, systemImage: icon, color: color)
        }
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

    private var title: String {
        hasPrepared ? (isPhotoRequired ? "拍照签到" : "普通签到") : "签到"
    }

    private var icon: String {
        switch state {
        case .loading, .signing: "hourglass"
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
        case .ready:
            isPhotoRequired ? (multi.isCurrentAlreadySigned(model.user) ? "当前账号已签到，可选择其他账号签到" : "通过相机或相册选择图片签到") : "点击下方按钮签到"
        case .signing:
            isPhotoRequired ? "正在压缩、上传图片并提交签到…" : "正在提交签到…"
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

    private var canChoosePhoto: Bool {
        guard hasPrepared, isPhotoRequired else { return false }
        return state == .ready || state.isFailure || (state == .success && !multi.pendingIDs(current: model.user).isEmpty)
    }

    private var canSubmitOrdinary: Bool {
        guard hasPrepared, !isPhotoRequired else { return false }
        return state == .ready || state.isFailure
    }

    private func updateState(_ newState: State) {
        withAnimation { state = newState }
    }

    private func prepare() async {
        multi.load(current: model.user)
        hasPrepared = false
        updateState(.loading)
        do {
            switch try await model.prepareOrdinaryOrPhotoSign(activity) {
            case .ready(let isPhotoRequired):
                self.isPhotoRequired = isPhotoRequired
                hasPrepared = true
                updateState(.ready)
            case .alreadySigned(let isPhotoRequired):
                self.isPhotoRequired = isPhotoRequired
                hasPrepared = true
                if isPhotoRequired {
                    multi.markCurrent(model.user, as: .alreadySigned)
                    updateState(.ready)
                } else { updateState(.alreadySigned) }
            case .expired(let isPhotoRequired):
                self.isPhotoRequired = isPhotoRequired
                hasPrepared = true
                updateState(.expired)
            }
        } catch {
            updateState(.failure(error.localizedDescription))
        }
    }

    private func loadAndSubmit(_ item: PhotosPickerItem) async {
        updateState(.signing)
        defer { photoPickerItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw ChaoxingError.invalidInput("无法读取选中的图片")
            }
            selectedImage = image
            await submit(image)
        } catch {
            updateState(.failure(error.localizedDescription))
        }
    }

    private func submit(_ image: UIImage) async {
        guard !multi.pendingIDs(current: model.user).isEmpty else { updateState(.ready); return }
        updateState(.signing)
        do {
            guard let jpegData = image.signJPEGData() else {
                throw ChaoxingError.invalidInput("无法处理选中的图片")
            }
            let failed = await multi.sign(model: model) {
                try await model.signForCurrent { api in
                    _ = try await api.signPhoto(activity, jpegData: jpegData)
                    return .success
                }
            } other: { api in
                switch try await api.prepareOrdinaryOrPhotoSign(activity) {
                case .ready(isPhotoRequired: true):
                    _ = try await api.signPhoto(activity, jpegData: jpegData)
                    return .success
                case .ready(isPhotoRequired: false):
                    throw ChaoxingError.unsupportedSign("该账号无需上传照片")
                case .alreadySigned: return .alreadySigned
                case .expired: return .expired
                }
            }
            updateState(failed ? .failure("部分账号签到失败，可重试") : .success)
        } catch {
            handleSignError(error)
        }
    }

    private func submitOrdinary() async {
        updateState(.signing)
        do {
            _ = try await model.signOrdinary(activity)
            updateState(.success)
        } catch {
            handleSignError(error)
        }
    }

    private func handleSignError(_ error: Error) {
        if let error = error as? ChaoxingError {
            switch error {
            case .alreadySigned: updateState(.alreadySigned)
            case .signExpired: updateState(.expired)
            default: updateState(.failure(error.localizedDescription))
            }
        } else {
            updateState(.failure(error.localizedDescription))
        }
    }
}

private extension PhotoSignView.State {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}

private extension UIImage {
    func signJPEGData(maxDimension: CGFloat = 2048) -> Data? {
        guard size.width > 0, size.height > 0 else { return nil }
        let ratio = min(1, maxDimension / max(size.width, size.height))
        let targetSize = CGSize(
            width: max(1, (size.width * ratio).rounded()),
            height: max(1, (size.height * ratio).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return normalized.jpegData(compressionQuality: 0.5)
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                parent.onCancel()
                return
            }
            parent.onImage(image)
        }
    }
}
