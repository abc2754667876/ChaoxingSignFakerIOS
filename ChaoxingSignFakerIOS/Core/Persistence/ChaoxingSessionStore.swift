import Foundation
import Security

struct PersistedChaoxingSession {
    let session: ChaoxingSession
    let cookies: [HTTPCookie]
}

struct ChaoxingSessionStore {
    private static let service = "com.chengzhizhang.ChaoxingSignFakerIOS.session"
    private static let account = "current-session"

    func load() -> PersistedChaoxingSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let stored = try? JSONDecoder().decode(StoredSession.self, from: data) else {
            return nil
        }
        return PersistedChaoxingSession(
            session: stored.session,
            cookies: stored.cookies.compactMap(\.httpCookie)
        )
    }

    func save(session: ChaoxingSession, cookies: [HTTPCookie]) {
        let stored = StoredSession(
            session: session,
            cookies: cookies.map { StoredCookie($0) }
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct StoredSession: Codable {
    let session: ChaoxingSession
    let cookies: [StoredCookie]
}

private struct StoredCookie: Codable {
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

    var httpCookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .version: "0"
        ]
        if let expiresDate {
            properties[.expires] = expiresDate
        }
        if isSecure {
            properties[.secure] = "TRUE"
        }
        return HTTPCookie(properties: properties)
    }
}
