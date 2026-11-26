import Foundation

struct FacePhotoStore {
    private let accounts = OtherUserStore()

    func photos(for user: ChaoxingUser, isCurrent: Bool) -> [OtherUserFace] {
        if isCurrent {
            guard let data = UserDefaults.standard.data(forKey: key(user)) else { return [] }
            return (try? JSONDecoder().decode([OtherUserFace].self, from: data)) ?? []
        }
        return accounts.load().first { $0.session.user.uid == user.uid }?.faces ?? []
    }

    func save(_ photos: [OtherUserFace], for user: ChaoxingUser, isCurrent: Bool) throws {
        guard photos.count <= 5 else { throw ChaoxingError.invalidInput("最多只能保存 5 张人脸照片") }
        if isCurrent {
            UserDefaults.standard.set(try JSONEncoder().encode(photos), forKey: key(user))
        } else {
            var stored = accounts.load()
            guard let index = stored.firstIndex(where: { $0.session.user.uid == user.uid }) else {
                throw ChaoxingError.invalidInput("账号已从多账号列表移除")
            }
            stored[index].faces = photos
            try accounts.save(stored)
        }
    }

    func photoURL(for user: ChaoxingUser, isCurrent: Bool, objectID: String) throws -> URL {
        guard !objectID.isEmpty, objectID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
            throw ChaoxingError.invalidInput("人脸照片 ID 无效")
        }
        return try accounts.photoURL(accountID: isCurrent ? "profile-\(user.uid)" : user.phoneNumber, faceID: objectID)
    }

    func add(_ data: Data, objectID: String, for user: ChaoxingUser, isCurrent: Bool) throws {
        var photos = photos(for: user, isCurrent: isCurrent)
        guard !photos.contains(where: { $0.id == objectID }) else { return }
        guard photos.count < 5 else { throw ChaoxingError.invalidInput("最多只能保存 5 张人脸照片") }
        let url = try photoURL(for: user, isCurrent: isCurrent, objectID: objectID)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        photos.append(OtherUserFace(id: objectID, addedAt: Date()))
        do { try save(photos, for: user, isCurrent: isCurrent) }
        catch { try? FileManager.default.removeItem(at: url); throw error }
    }

    func recordUse(objectID: String, for user: ChaoxingUser, isCurrent: Bool, isFailure: Bool) {
        var photos = photos(for: user, isCurrent: isCurrent)
        guard let index = photos.firstIndex(where: { $0.id == objectID }) else { return }
        photos[index].useCount = (photos[index].useCount ?? 0) + 1
        photos[index].hasFailed = (photos[index].hasFailed ?? false) || isFailure
        try? save(photos, for: user, isCurrent: isCurrent)
    }

    private func key(_ user: ChaoxingUser) -> String { "profile.faces.\(user.uid)" }
}
