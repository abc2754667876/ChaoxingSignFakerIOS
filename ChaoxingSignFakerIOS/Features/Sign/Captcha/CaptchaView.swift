import SwiftUI
import UIKit

struct CaptchaView: View {
    let request: CaptchaCoordinator.Request
    let coordinator: CaptchaCoordinator
    @State private var challenge: ChaoxingCaptcha?
    @State private var shade: UIImage?
    @State private var cutout: UIImage?
    @State private var progress = 0.0
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var operation: Task<Void, Never>?
    @State private var processingMessage = "正在加载验证码…"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        Text(request.user.name).font(.headline)
                        Text("拖动滑块，使拼图与缺口重合").foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            Color(.secondarySystemGroupedBackground)
                            if let shade, let cutout {
                                Image(uiImage: shade).resizable()
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                Image(uiImage: cutout).resizable()
                                    .frame(width: geometry.size.width * 56 / 320, height: geometry.size.height)
                                    .offset(x: progress * geometry.size.width * 264 / 320)
                            }
                            if isProcessing {
                                ProgressView(processingMessage).frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.ultraThinMaterial)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .aspectRatio(2, contentMode: .fit)
                    .accessibilityLabel("滑块验证码图片")
                    Slider(value: $progress, in: 0...1, onEditingChanged: { isEditing in
                        if !isEditing { startChecking() }
                    })
                    .accessibilityLabel("拼图位置")
                    .disabled(isProcessing || challenge == nil)
                    if let errorMessage {
                        Text(errorMessage).font(.subheadline).foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                    }
                    Button("刷新验证码", systemImage: "arrow.clockwise") {
                        operation = Task { await refresh() }
                    }
                    .disabled(isProcessing)
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("滑块验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", role: .cancel) {
                        operation?.cancel()
                        coordinator.request = nil
                    }
                }
            }
            .task { await refresh(automatically: true) }
            .onDisappear { operation?.cancel() }
        }
    }

    private var isCurrentRequest: Bool {
        coordinator.request?.id == request.id && request.api.session?.user.uid == request.user.uid
    }

    @discardableResult
    private func loadChallenge() async throws -> Data {
        challenge = nil
        shade = nil
        cutout = nil
        progress = 0
        let next = try await request.api.captcha(for: request.activity)
        async let shadeResponse = request.api.http.send(next.shadeImageURL)
        async let cutoutResponse = request.api.http.send(next.cutoutImageURL)
        let (background, piece) = try await (shadeResponse, cutoutResponse)
        try Task.checkCancellation()
        guard isCurrentRequest else { throw ChaoxingError.signCancelled }
        guard let backgroundImage = UIImage(data: background.data), let pieceImage = UIImage(data: piece.data) else {
            throw ChaoxingError.invalidResponse("验证码图片加载失败，请刷新")
        }
        shade = backgroundImage
        cutout = pieceImage
        challenge = next
        return background.data
    }

    private func refresh(automatically: Bool = false) async {
        guard !isProcessing, isCurrentRequest else { return }
        isProcessing = true
        errorMessage = nil
        processingMessage = "正在加载验证码…"
        defer { isProcessing = false }
        do {
            let data = try await loadChallenge()
            if automatically, let challenge {
                processingMessage = "正在识别验证码…"
                let result = try await CaptchaAutomaticResolver.resolve(imageData: data) { data in
                    try await CaptchaPredictor.shared.predict(imageData: data)
                } verify: { offset in
                    try Task.checkCancellation()
                    guard isCurrentRequest else { throw ChaoxingError.signCancelled }
                    return try await request.api.checkCaptcha(challenge, xPosition: offset, for: request.activity)
                }
                try Task.checkCancellation()
                guard isCurrentRequest else { return }
                switch result {
                case .solved(let validate): coordinator.complete(validate, requestID: request.id)
                case .manual(let requiresRefresh):
                    if requiresRefresh {
                        processingMessage = "正在刷新验证码…"
                        try await loadChallenge()
                    }
                    errorMessage = "请拖动滑块完成验证"
                }
            }
        }
        catch is CancellationError { }
        catch { if isCurrentRequest { errorMessage = error.localizedDescription } }
    }

    private func startChecking() {
        guard !isProcessing, let challenge, isCurrentRequest else { return }
        isProcessing = true
        processingMessage = "正在校验验证码…"
        errorMessage = nil
        operation = Task {
            defer { isProcessing = false }
            do {
                let validate = try await request.api.checkCaptcha(challenge, progress: progress, for: request.activity)
                try Task.checkCancellation()
                guard isCurrentRequest else { return }
                if let validate {
                    coordinator.complete(validate, requestID: request.id)
                    return
                }
                errorMessage = "验证未通过，请重新拖动滑块"
            } catch is CancellationError {
                return
            } catch {
                guard isCurrentRequest else { return }
                errorMessage = error.localizedDescription
            }
            do { try await loadChallenge() }
            catch is CancellationError { }
            catch { if isCurrentRequest { errorMessage = error.localizedDescription } }
        }
    }
}
