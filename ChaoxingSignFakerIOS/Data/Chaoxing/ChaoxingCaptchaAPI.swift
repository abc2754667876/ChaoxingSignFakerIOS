import Foundation

extension ChaoxingAPI {
    private static let captchaID = "Qt9FIw9o4pwRjOyqM6yizZBh682qN2TU"

    func captcha(for activity: ChaoxingActivity) async throws -> ChaoxingCaptcha {
        guard let current = session else { throw ChaoxingError.sessionExpired }
        let conf = try await http.send(
            URL(string: "https://captcha.chaoxing.com/captcha/get/conf")!,
            query: captchaQuery([("captchaId", Self.captchaID)])
        )
        let configuration = try Self.captchaJSON(conf.text)
        guard let timestamp = configuration.int64("t"), timestamp > 0, timestamp <= Int64.max - 300_000 else {
            throw ChaoxingError.invalidResponse("验证码配置缺少时间戳")
        }
        let type = "slide"
        let version = "1.1.20"
        let key = ChaoxingCrypto.md5("\(timestamp)\(UUID().uuidString.lowercased())")
        let iv = ChaoxingCrypto.md5("\(Self.captchaID)\(type)\(Self.captchaMilliseconds)\(UUID().uuidString.lowercased())")
        let token = ChaoxingCrypto.md5("\(timestamp)\(Self.captchaID)\(type)\(key)") + ":\(timestamp + 300_000)"
        let response = try await http.send(
            URL(string: "https://captcha.chaoxing.com/captcha/get/verification/image")!,
            query: captchaQuery([
                ("captchaId", Self.captchaID), ("type", type), ("version", version),
                ("captchaKey", key), ("token", token), ("iv", iv),
                ("referer", preSignURL(activity: activity, session: current).absoluteString)
            ])
        )
        try Task.checkCancellation()
        guard session?.user.uid == current.user.uid else { throw ChaoxingError.sessionExpired }
        let json = try Self.captchaJSON(response.text)
        guard let image = json.object("imageVerificationVo"),
              let token = json.string("token"), !token.isEmpty,
              let shade = image.string("shadeImage"), let shadeURL = Self.captchaImageURL(shade),
              let cutout = image.string("cutoutImage"), let cutoutURL = Self.captchaImageURL(cutout) else {
            throw ChaoxingError.invalidResponse("验证码图片信息不完整")
        }
        return ChaoxingCaptcha(captchaID: Self.captchaID, type: type, version: version,
                              token: token, iv: iv, shadeImageURL: shadeURL,
                              cutoutImageURL: cutoutURL, expiresAt: .now.addingTimeInterval(300))
    }

    func checkCaptcha(_ challenge: ChaoxingCaptcha, progress: Double, for activity: ChaoxingActivity) async throws -> String? {
        guard let current = session else { throw ChaoxingError.sessionExpired }
        guard progress.isFinite else { throw ChaoxingError.invalidInput("滑块位置无效") }
        guard challenge.expiresAt > .now else { throw ChaoxingError.captchaFailed("验证码已过期，请刷新") }
        let response = try await http.send(
            URL(string: "https://captcha.chaoxing.com/captcha/check/verification/result")!,
            query: captchaQuery([
                ("captchaId", challenge.captchaID), ("type", challenge.type), ("token", challenge.token),
                ("textClickArr", "[{\"x\":\(ChaoxingCaptcha.verificationX(progress: progress))}]"),
                ("coordinate", "[]"), ("runEnv", "10"), ("version", challenge.version),
                ("t", "a"), ("iv", challenge.iv)
            ]),
            headers: ["Referer": preSignURL(activity: activity, session: current).absoluteString]
        )
        try Task.checkCancellation()
        guard session?.user.uid == current.user.uid else { throw ChaoxingError.sessionExpired }
        let json = try Self.captchaJSON(response.text)
        guard let isValid = json.boolean("result") else {
            throw ChaoxingError.invalidResponse("验证码校验响应缺少结果")
        }
        guard isValid else { return nil }
        let extra: JSONObject?
        if let object = json.object("extraData") {
            extra = object
        } else if let text = json.string("extraData") {
            extra = (try? JSONReader.object(from: Data(text.utf8)))
                ?? (try? JSONReader.object(from: Data(text.replacingOccurrences(of: "\\\"", with: "\"").utf8)))
        } else {
            extra = nil
        }
        guard let validate = extra?.string("validate"), !validate.isEmpty else {
            throw ChaoxingError.invalidResponse("验证码校验未返回有效凭证")
        }
        return validate
    }

    static func captchaJSON(_ text: String) throws -> JSONObject {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasSuffix(";") { value.removeLast(); value = value.trimmingCharacters(in: .whitespacesAndNewlines) }
        let prefix = "cx_captcha_function("
        guard value.hasPrefix(prefix), value.hasSuffix(")") else {
            throw ChaoxingError.invalidResponse("验证码响应格式无效")
        }
        let json = try JSONReader.object(from: Data(value.dropFirst(prefix.count).dropLast().utf8))
        if json.integer("error") == 1 {
            throw ChaoxingError.captchaFailed(json.string("msg") ?? "验证码服务返回错误，请刷新重试")
        }
        return json
    }

    private static var captchaMilliseconds: Int64 { Int64(Date.now.timeIntervalSince1970 * 1000) }

    private func captchaQuery(_ values: [(String, String)]) -> [URLQueryItem] {
        ([ ("callback", "cx_captcha_function"), ("_", String(Self.captchaMilliseconds)) ] + values)
            .map { URLQueryItem(name: $0.0, value: $0.1) }
    }

    private static func captchaImageURL(_ value: String) -> URL? {
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased()), url.host != nil else { return nil }
        return url
    }
}
