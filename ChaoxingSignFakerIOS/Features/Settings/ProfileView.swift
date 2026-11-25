import PhotosUI
import SwiftUI
import UIKit

struct ProfileView: View {
    @Bindable var model: AppModel
    @State private var showLogoutConfirmation = false
    @State private var showFaces = false
    @State private var faces: [OtherUserFace] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isSavingPhoto = false
    @State private var pendingFaceDeletion: String?
    @State private var errorMessage: String?

    private let photoStore = OtherUserStore()
    private let androidURL = URL(string: "https://github.com/aquamarine5/ChaoxingSignFaker")!
    private let iosURL = URL(string: "https://github.com/abc2754667876/ChaoxingSignFakerIOS")!

    var body: some View {
        NavigationStack {
            List {
                Section("当前账号") {
                    if let user = model.user {
                        HStack(spacing: 12) {
                            avatar(for: user)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name).font(.headline)
                                Text(masked(user.phoneNumber)).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { showLogoutConfirmation = true } label: {
                                Image(systemName: "rectangle.portrait.and.arrow.forward")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("退出登录")
                            .confirmationDialog("退出登录", isPresented: $showLogoutConfirmation) {
                                Button("退出登录", role: .destructive) { model.logout() }
                                Button("取消", role: .cancel) {}
                            } message: { Text("确定退出当前账号吗？") }
                        }
                    }
                }

                Section("个人信息") {
                    HStack {
                        Image(systemName: "building.columns").foregroundStyle(.blue)
                        Text("院校机构")
                        Spacer()
                        if let user = model.user, !user.schools.isEmpty {
                            Picker("院校机构", selection: Binding(
                                get: { model.configuredFID ?? user.defaultFID },
                                set: { model.setConfiguredFID($0) }
                            )) {
                                ForEach(user.schools) { school in
                                    Text(school.name).tag(school.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                        } else {
                            Text("暂无可选机构").foregroundStyle(.secondary)
                        }
                    }
                    Button { showFaces = true } label: {
                        HStack {
                            Image(systemName: "person.fill.viewfinder").foregroundStyle(.blue)
                            Text("管理人脸照片").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                }

                Section("项目仓库与赞助") {
                    Link(destination: androidURL) {
                        repositoryRow("aquamarine5/ChaoxingSignFaker")
                    }
                    Link(destination: iosURL) {
                        repositoryRow("abc2754667876/ChaoxingSignFakerIOS")
                    }
                }

                Text("*本项目在aquamarine5/ChaoxingSignFaker基础上进行iOS移植开发，请支持原作者\n**本项目仅作为交流学习使用，通过本项目加深前端设计、接口调用、数据库使用、网络通信安全等方面知识的理解。请勿将此项目用作商业用途和任何不正当违规违法行为。任何人或组织使用项目或项目中的代码进行的任何不正当违规和违法行为与作者无关，作者不承担任何因使用本应用而导致的法律或其他任何责任。")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .listRowBackground(Color.clear)
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showFaces) { faceSheet }
    }

    private func repositoryRow(_ name: String) -> some View {
        HStack {
            Image(systemName: "shippingbox").foregroundStyle(.blue)
            Text(name).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
    }

    private func avatar(for user: ChaoxingUser) -> some View {
        Group {
            if let url = user.avatarURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                    Image(systemName: "person.circle.fill").resizable().foregroundStyle(.blue)
                }
            } else {
                Image(systemName: "person.circle.fill").resizable().foregroundStyle(.blue)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
    }

    private func masked(_ value: String) -> String {
        guard value.count >= 7 else { return value }
        return "\(value.prefix(3))****\(value.suffix(4))"
    }

    private var faceSheet: some View {
        NavigationStack {
            VStack {
                if faces.isEmpty {
                    ContentUnavailableView("人脸照片", systemImage: "person.fill.viewfinder", description: Text("暂无人脸照片，可通过相册或拍照添加"))
                } else {
                    List {
                        Section("人脸照片（\(faces.count)/5）") {
                            ForEach(Array(faces.enumerated()), id: \.element.id) { index, face in
                                HStack(spacing: 12) {
                                    if let user = model.user,
                                       let url = try? photoStore.photoURL(accountID: photoAccountID(for: user), faceID: face.id),
                                       let image = UIImage(contentsOfFile: url.path) {
                                        Image(uiImage: image)
                                            .resizable().scaledToFill()
                                            .frame(width: 96, height: 56)
                                            .clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    VStack(alignment: .leading) {
                                        Text("照片\(index + 1)").font(.headline)
                                        Text(face.addedAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) { pendingFaceDeletion = face.id } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .swipeActions {
                                    Button("删除", role: .destructive) { pendingFaceDeletion = face.id }
                                }
                            }
                        }
                    }
                }
                VStack(spacing: 8) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text("从相册选择照片").frame(maxWidth: .infinity).frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { showCamera = true } label: {
                        Text("从相机拍摄照片").frame(maxWidth: .infinity).frame(height: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                }
                .disabled(faces.count >= 5 || isSavingPhoto)
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("管理人脸照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { showFaces = false } } }
            .onAppear { loadFaces() }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    defer { photoItem = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self),
                              let image = UIImage(data: data) else {
                            throw ChaoxingError.invalidInput("无法读取照片")
                        }
                        await savePhoto(image)
                    } catch { errorMessage = error.localizedDescription }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                OtherUserCameraPicker { image in
                    showCamera = false
                    Task { await savePhoto(image) }
                } onCancel: { showCamera = false }
            }
            .alert("删除照片", isPresented: Binding(get: { pendingFaceDeletion != nil }, set: { if !$0 { pendingFaceDeletion = nil } })) {
                Button("删除", role: .destructive) {
                    if let id = pendingFaceDeletion { deleteFace(id) }
                    pendingFaceDeletion = nil
                }
                Button("取消", role: .cancel) { pendingFaceDeletion = nil }
            } message: { Text("确定删除这张人脸照片吗？") }
            .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func photoAccountID(for user: ChaoxingUser) -> String { "profile-\(user.uid)" }
    private func faceKey(for user: ChaoxingUser) -> String { "profile.faces.\(user.uid)" }

    private func loadFaces() {
        guard let user = model.user,
              let data = UserDefaults.standard.data(forKey: faceKey(for: user)) else {
            faces = []
            return
        }
        faces = (try? JSONDecoder().decode([OtherUserFace].self, from: data)) ?? []
    }

    private func saveFaces(_ updated: [OtherUserFace], for user: ChaoxingUser) throws {
        let data = try JSONEncoder().encode(updated)
        UserDefaults.standard.set(data, forKey: faceKey(for: user))
        faces = updated
    }

    private func savePhoto(_ image: UIImage) async {
        guard !isSavingPhoto, faces.count < 5, let user = model.user else { return }
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            errorMessage = "无法处理照片"
            return
        }
        isSavingPhoto = true
        defer { isSavingPhoto = false }
        do {
            let objectID = try await model.uploadFacePhoto(data)
            guard model.user?.uid == user.uid, faces.count < 5 else { return }
            let url = try photoStore.photoURL(accountID: photoAccountID(for: user), faceID: objectID)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            do { try saveFaces(faces + [OtherUserFace(id: objectID, addedAt: Date())], for: user) }
            catch { try? FileManager.default.removeItem(at: url); throw error }
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteFace(_ id: String) {
        guard let user = model.user else { return }
        do {
            try saveFaces(faces.filter { $0.id != id }, for: user)
            if let url = try? photoStore.photoURL(accountID: photoAccountID(for: user), faceID: id) {
                try? FileManager.default.removeItem(at: url)
            }
        } catch { errorMessage = error.localizedDescription }
    }
}

#Preview { ProfileView(model: AppModel()) }
