import Foundation
import Security
import UIKit

struct OtherUserFace: Codable, Identifiable, Hashable {
    let id: String
    let addedAt: Date
}

struct OtherUserAccount: Codable, Identifiable {
    var id: String { session.user.phoneNumber }
    var session: ChaoxingSession
    var cookies: [OtherUserCookie]
    var password: String
    var faces: [OtherUserFace]
}

struct OtherUserCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expiresDate: Date?
    let isSecure: Bool

    init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expiresDate = cookie.expiresDate
        isSecure = cookie.isSecure
    }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: value, .domain: domain, .path: path, .version: "0"
        ]
        if let expiresDate { properties[.expires] = expiresDate }
        if isSecure { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}

extension HTTPCookie {
    func replacingValue(_ newValue: String) -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name, .value: newValue, .domain: domain, .path: path, .version: "0"
        ]
        if let expiresDate { properties[.expires] = expiresDate }
        if isSecure { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}

struct OtherUserStore {
    private let service = "com.chengzhizhang.ChaoxingSignFakerIOS.other-users"

    func load() -> [OtherUserAccount] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "accounts",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return [] }
        return (try? JSONDecoder().decode([OtherUserAccount].self, from: data)) ?? []
    }

    func save(_ accounts: [OtherUserAccount]) throws {
        let data = try JSONEncoder().encode(accounts)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "accounts"
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw ChaoxingError.server("保存账号失败（\(status)）") }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw ChaoxingError.server("保存账号失败（\(addStatus)）") }
    }

    func photoURL(accountID: String, faceID: String) throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let accountFolder = base.appendingPathComponent("OtherUserFaces", isDirectory: true)
            .appendingPathComponent(accountID, isDirectory: true)
        try FileManager.default.createDirectory(at: accountFolder, withIntermediateDirectories: true)
        return accountFolder.appendingPathComponent(faceID).appendingPathExtension("jpg")
    }

    func deletePhotos(for account: OtherUserAccount) {
        for face in account.faces {
            if let url = try? photoURL(accountID: account.id, faceID: face.id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
