import Foundation
import CryptoKit

struct ChaoxingSession: Sendable {
    let user: ChaoxingUser
    let configuredFID: Int
    let deviceCode: String
}

enum DeviceCodeStore {
    private static let key = "chaoxing.device-code"

    static func loadOrCreate() -> String {
        if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
            return value
        }
        let source = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let digest = Array(CryptoKit.SHA256.hash(data: Data(source.utf8)))
        let value = Data(digest + digest).base64EncodedString()
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}

