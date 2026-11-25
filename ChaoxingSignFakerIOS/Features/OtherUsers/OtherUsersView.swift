import PhotosUI
import SwiftUI
import UIKit

struct OtherUsersView: View {
    let currentUser: ChaoxingUser?
    private let store = OtherUserStore()
    @State private var accounts: [OtherUserAccount] = []
    @State private var showAddUser = false
    @State private var username = ""
    @State private var password = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var deleteAccountID: String?
    @State private var collegeAccountID: String?
    @State private var photoAccountID: String?
    @State private var deleteFaceID: String?
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var isSavingPhoto = false

    var body: some View {
        NavigationStack {
            Group {
                if accounts.isEmpty {
                    ContentUnavailableView("多账号", systemImage: "person.2", description: Text("暂无其他账号，可通过右上角添加"))
                } else {
                    List {
                        Section("其他账号") {
                            ForEach(accounts) { account in
                                HStack(spacing: 12) {
                                    avatar(for: account)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(account.session.user.name).font(.headline)
                                        Text(masked(account.id)).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button { collegeAccountID = account.id } label: {
                                        Image(systemName: "building.columns")
                                    }.buttonStyle(.borderless).accessibilityLabel("设置机构")
                                    Button { photoAccountID = account.id } label: {
                                        Image(systemName: "person.fill.viewfinder")
                                    }.buttonStyle(.borderless).accessibilityLabel("管理人脸照片")
                                    Button(role: .destructive) { deleteAccountID = account.id } label: {
                                        Image(systemName: "trash")
                                    }.buttonStyle(.borderless).accessibilityLabel("删除账号")
                                }
                                .swipeActions {
                                    Button("删除", role: .destructive) { deleteAccountID = account.id }
                                }
                            }
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("多账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddUser = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .onAppear { accounts = store.load() }
        .sheet(isPresented: $showAddUser) { addUserSheet }
        .sheet(isPresented: Binding(get: { collegeAccountID != nil }, set: { if !$0 { collegeAccountID = nil } })) {
            if let account = account(for: collegeAccountID) { collegeSheet(account) }
        }
        .sheet(isPresented: Binding(get: { photoAccountID != nil }, set: { if !$0 { photoAccountID = nil } })) {
            if let account = account(for: photoAccountID) { photoSheet(account) }
        }
        .alert("删除账号", isPresented: Binding(get: { deleteAccountID != nil }, set: { if !$0 { deleteAccountID = nil } })) {
            Button("删除", role: .destructive) { if let id = deleteAccountID { deleteAccount(id) }; deleteAccountID = nil }
            Button("取消", role: .cancel) { deleteAccountID = nil }
        } message: { Text("确定删除这个账号及其本机人脸照片吗？") }
        .alert("删除照片", isPresented: Binding(get: { deleteFaceID != nil }, set: { if !$0 { deleteFaceID = nil } })) {
            Button("删除", role: .destructive) { if let id = deleteFaceID { deleteFace(id) }; deleteFaceID = nil }
            Button("取消", role: .cancel) { deleteFaceID = nil }
        } message: { Text("确定删除这张人脸照片吗？") }
        .alert("操作失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func avatar(for account: OtherUserAccount) -> some View {
        Group {
            if let url = account.session.user.avatarURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                    Image(systemName: "person.circle.fill").resizable().foregroundStyle(.blue)
                }
            } else {
                Image(systemName: "person.circle.fill").resizable().foregroundStyle(.blue)
            }
        }
        .frame(width: 48, height: 48).clipShape(Circle())
    }

    private func masked(_ value: String) -> String {
        guard value.count >= 7 else { return value }
        return "\(value.prefix(3))****\(value.suffix(4))"
    }

    private func account(for id: String?) -> OtherUserAccount? {
        accounts.first { $0.id == id }
    }

    private var addUserSheet: some View {
        NavigationStack {
            Form {
                Section("学习通账号") {
                    TextField("手机号或账号", text: $username)
                        .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("密码", text: $password).textContentType(.password)
                }
                Section {
                    Button { Task { await addUser() } } label: {
                        HStack {
                            Spacer()
                            if isAdding { ProgressView() } else { Text("验证并添加账号") }
                            Spacer()
                        }
                    }
                    .disabled(isAdding || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                }
            }
            .navigationTitle("添加账号").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { showAddUser = false } } }
        }
    }

    private func addUser() async {
        isAdding = true
        defer { isAdding = false }
        do {
            let cookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "other-user-\(UUID().uuidString)")
            let api = ChaoxingAPI(http: HTTPClient(cookieStorage: cookieStorage))
            let session = try await api.login(phoneNumber: username, password: password)
            guard session.user.uid != currentUser?.uid else {
                throw ChaoxingError.invalidInput("不能添加当前登录的账号")
            }
            var updated = accounts
            let existingIndex = updated.firstIndex { $0.session.user.uid == session.user.uid }
            if let existingIndex, updated[existingIndex].id != session.user.phoneNumber {
                throw ChaoxingError.invalidInput("该账号已通过其他登录名添加")
            }
            let account = OtherUserAccount(session: session, cookies: api.authenticationCookies.map(OtherUserCookie.init), password: password, faces: existingIndex.map { updated[$0].faces } ?? [])
            if let existingIndex { updated[existingIndex] = account } else { updated.append(account) }
            try store.save(updated)
            accounts = updated
            username = ""
            password = ""
            showAddUser = false
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteAccount(_ id: String) {
        guard let account = account(for: id) else { return }
        do {
            let updated = accounts.filter { $0.id != id }
            try store.save(updated)
            accounts = updated
            store.deletePhotos(for: account)
        } catch { errorMessage = error.localizedDescription }
    }

    private func collegeSheet(_ account: OtherUserAccount) -> some View {
        NavigationStack {
            Form {
                Section("选择院校机构") {
                    if account.session.user.schools.isEmpty {
                        Text("此账号暂无可选机构").foregroundStyle(.secondary)
                    } else {
                        Picker("院校机构", selection: Binding(
                            get: { self.account(for: account.id)?.session.configuredFID ?? account.session.configuredFID },
                            set: { updateFID($0, for: account.id) }
                        )) {
                            ForEach(account.session.user.schools) { school in
                                Text(school.name).tag(school.id)
                            }
                        }
                    }
                }
            }
            .navigationTitle("为\(account.session.user.name)管理院校机构")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { collegeAccountID = nil } } }
        }
    }

    private func updateFID(_ fid: Int, for id: String) {
        guard let index = accounts.firstIndex(where: { $0.id == id }),
              accounts[index].session.user.schools.contains(where: { $0.id == fid }) else { return }
        var updated = accounts
        let old = updated[index].session
        updated[index].session = ChaoxingSession(user: old.user, configuredFID: fid, deviceCode: old.deviceCode)
        do { try store.save(updated); accounts = updated }
        catch { errorMessage = error.localizedDescription }
    }

    private func photoSheet(_ account: OtherUserAccount) -> some View {
        let current = self.account(for: account.id) ?? account
        return NavigationStack {
            VStack {
                if current.faces.isEmpty {
                    ContentUnavailableView("人脸照片", systemImage: "person.fill.viewfinder", description: Text("暂无人脸照片，可通过相册或拍照添加"))
                } else {
                    List {
                        Section("人脸照片（\(current.faces.count)/5）") {
                            ForEach(Array(current.faces.enumerated()), id: \.element.id) { index, face in
                                HStack(spacing: 12) {
                                    if let url = try? store.photoURL(accountID: current.id, faceID: face.id),
                                       let image = UIImage(contentsOfFile: url.path) {
                                        Image(uiImage: image).resizable().scaledToFill().frame(width: 96, height: 56).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                    VStack(alignment: .leading) {
                                        Text("照片\(index + 1)").font(.headline)
                                        Text(face.addedAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) { deleteFaceID = face.id } label: { Image(systemName: "trash") }
                                        .buttonStyle(.borderless)
                                }
                                .swipeActions { Button("删除", role: .destructive) { deleteFaceID = face.id } }
                            }
                        }
                    }
                }
                VStack(spacing: 8) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Text("从相册选择照片").frame(maxWidth: .infinity).frame(height: 48)
                    }.buttonStyle(.borderedProminent)
                    Button { showCamera = true } label: {
                        Text("从相机拍摄照片").frame(maxWidth: .infinity).frame(height: 48)
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                }
                .disabled(current.faces.count >= 5 || isSavingPhoto)
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("为\(current.session.user.name)管理人脸照片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { photoAccountID = nil } } }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    defer { photoItem = nil }
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                            throw ChaoxingError.invalidInput("无法读取照片")
                        }
                        await savePhoto(image, for: account.id)
                    } catch { errorMessage = error.localizedDescription }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                OtherUserCameraPicker { image in
                    showCamera = false
                    Task { await savePhoto(image, for: account.id) }
                } onCancel: { showCamera = false }
            }
        }
    }

    private func savePhoto(_ image: UIImage, for id: String) async {
        guard !isSavingPhoto, let account = account(for: id), account.faces.count < 5 else { return }
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            errorMessage = "无法处理照片"
            return
        }
        isSavingPhoto = true
        defer { isSavingPhoto = false }
        do {
            let cookieStorage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "face-upload-\(UUID().uuidString)")
            let api = ChaoxingAPI(http: HTTPClient(cookieStorage: cookieStorage))
            api.restore(account.session, cookies: account.cookies.compactMap(\.cookie))
            let objectID = try await api.uploadFacePhoto(data)
            guard let index = accounts.firstIndex(where: { $0.id == id }), accounts[index].faces.count < 5 else { return }
            let url = try store.photoURL(accountID: id, faceID: objectID)
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
            var updated = accounts
            updated[index].faces.append(OtherUserFace(id: objectID, addedAt: Date()))
            do { try store.save(updated); accounts = updated }
            catch { try? FileManager.default.removeItem(at: url); throw error }
        } catch { errorMessage = error.localizedDescription }
    }

    private func deleteFace(_ faceID: String) {
        guard let id = photoAccountID, let index = accounts.firstIndex(where: { $0.id == id }) else { return }
        var updated = accounts
        updated[index].faces.removeAll { $0.id == faceID }
        do {
            try store.save(updated)
            accounts = updated
            if let url = try? store.photoURL(accountID: id, faceID: faceID) { try? FileManager.default.removeItem(at: url) }
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct OtherUserCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, onCancel: onCancel) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void
        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onImage(image) } else { onCancel() }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
    }
}

#Preview { OtherUsersView(currentUser: nil) }
