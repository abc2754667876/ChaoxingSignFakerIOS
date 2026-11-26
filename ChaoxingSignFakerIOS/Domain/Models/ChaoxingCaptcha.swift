import Foundation

struct ChaoxingCaptcha: Identifiable, Sendable {
    let id = UUID()
    let captchaID: String
    let type: String
    let version: String
    let token: String
    let iv: String
    let shadeImageURL: URL
    let cutoutImageURL: URL
    let expiresAt: Date

    static func verificationX(progress: Double) -> Int {
        Int(min(1, max(0, progress)) * 280 - 8)
    }
}
