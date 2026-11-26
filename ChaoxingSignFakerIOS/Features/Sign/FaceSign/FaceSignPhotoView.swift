import PhotosUI
import SwiftUI
import UIKit

struct FaceSignPhotoView: View {
    let request: FaceSignCoordinator.Request
    let coordinator: FaceSignCoordinator
    @State private var photos: [OtherUserFace] = []
    @State private var selectedID: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var isShowingCamera = false
    @State private var isProcessing = false
    @State private var isSavingToLocal = true
    @State private var errorMessage: String?
    private let store = FacePhotoStore()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section("签到账号") {
                        HStack(spacing: 12) {
                            AsyncImage(url: request.user.avatarURL) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Image(systemName: "person.circle.fill").resizable().foregroundStyle(.blue)
                            }
                            .frame(width: 48, height: 48).clipShape(Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(request.user.name).font(.headline)
                                Text("请选择该账号的人脸照片").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("人脸照片（\(photos.count)/5）") {
                        if photos.isEmpty {
                            ContentUnavailableView("暂无人脸照片", systemImage: "person.fill.viewfinder",
                                                   description: Text("可通过相册、拍照或学习通默认照片添加"))
                        }
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            Button { selectedID = photo.id } label: {
                                HStack(spacing: 12) {
                                    if let url = try? store.photoURL(for: request.user, isCurrent: request.isCurrent, objectID: photo.id),
                                       let image = UIImage(contentsOfFile: url.path) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                            .frame(width: 96, height: 56).clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("照片\(index + 1)").font(.headline).foregroundStyle(.primary)
                                        Text(photo.addedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.subheadline).foregroundStyle(.secondary)
                                        if photo.hasFailed == true {
                                            Text("曾校验失败，可更换其他照片").font(.caption).foregroundStyle(.orange)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: selectedID == photo.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(.tint)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if photos.count < 5 {
                        Section {
                            Toggle("保存新照片到本机", isOn: $isSavingToLocal)
                        } footer: {
                            Text("新照片会先上传，再用于本次人脸验证。")
                        }
                    }
                    if let errorMessage {
                        Section { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    }
                }
                .disabled(isProcessing)
                VStack(spacing: 8) {
                    if isProcessing {
                        ProgressView("正在处理人脸照片…").frame(maxWidth: .infinity, minHeight: 48)
                    } else {
                        if let selectedID {
                            Button { coordinator.choose(selectedID, requestID: request.id) } label: {
                                actionLabel("使用所选照片签到", systemImage: "person.fill.viewfinder")
                            }
                            .buttonStyle(.plain)
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            actionLabel("从相册选择照片", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(.plain)
                        Button { isShowingCamera = true } label: {
                            actionLabel("从相机拍摄照片", systemImage: "camera.fill")
                        }
                        .buttonStyle(.plain)
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                        Button("使用学习通默认照片") { Task { await useDefaultPhoto() } }
                            .frame(minHeight: 36)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("人脸验证")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", role: .cancel) { coordinator.request = nil }
                }
            }
            .interactiveDismissDisabled(isProcessing)
            .onAppear {
                photos = store.photos(for: request.user, isCurrent: request.isCurrent)
                selectedID = photos.first(where: { $0.hasFailed != true })?.id ?? photos.first?.id
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    isProcessing = true
                    defer { photoItem = nil; isProcessing = false }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                            throw ChaoxingError.invalidInput("无法读取照片")
                        }
                        try await upload(image)
                    } catch { errorMessage = error.localizedDescription }
                }
            }
            .fullScreenCover(isPresented: $isShowingCamera) {
                OtherUserCameraPicker { image in
                    isShowingCamera = false
                    Task {
                        isProcessing = true
                        defer { isProcessing = false }
                        do { try await upload(image) }
                        catch { errorMessage = error.localizedDescription }
                    }
                } onCancel: { isShowingCamera = false }
                .ignoresSafeArea()
            }
        }
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .fontWeight(.semibold).foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Color.accentColor, in: Capsule())
    }

    private func upload(_ image: UIImage) async throws {
        guard coordinator.request?.id == request.id else { return }
        guard image.size.width > 0, image.size.height > 0 else { throw ChaoxingError.invalidInput("无法处理照片") }
        let scale = min(1, 2048 / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = normalized.jpegData(compressionQuality: 0.85) else { throw ChaoxingError.invalidInput("无法处理照片") }
        let objectID = try await request.api.uploadFacePhoto(data)
        guard coordinator.request?.id == request.id else { return }
        if isSavingToLocal, photos.count < 5 {
            try store.add(data, objectID: objectID, for: request.user, isCurrent: request.isCurrent)
        }
        coordinator.choose(objectID, requestID: request.id)
    }

    private func useDefaultPhoto() async {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }
        do {
            let data = try await request.api.defaultFacePhoto()
            guard let image = UIImage(data: data) else { throw ChaoxingError.invalidResponse("默认人脸照片下载失败") }
            try await upload(image)
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct FaceSignSupport: ViewModifier {
    let model: AppModel
    let activity: ChaoxingActivity

    func body(content: Content) -> some View {
        @Bindable var coordinator = model.faceSign
        content
            .sheet(item: $coordinator.request, onDismiss: { coordinator.dismissSelection() }) { request in
                FaceSignPhotoView(request: request, coordinator: coordinator)
            }
            .onAppear { coordinator.activate(activityID: activity.id) }
            .onDisappear { coordinator.reset(activityID: activity.id) }
    }
}

extension View {
    func faceSignSupport(model: AppModel, activity: ChaoxingActivity) -> some View {
        modifier(FaceSignSupport(model: model, activity: activity))
    }
}

struct FaceSignRequirementLabel: View {
    let model: AppModel
    let activity: ChaoxingActivity

    var body: some View {
        if model.faceRequiredActivityIDs.contains(activity.id) {
            Label("本次签到需要人脸验证", systemImage: "person.fill.viewfinder")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
