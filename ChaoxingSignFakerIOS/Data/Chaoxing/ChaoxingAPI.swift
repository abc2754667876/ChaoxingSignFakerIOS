import Foundation

@MainActor
final class ChaoxingAPI {
    private enum Endpoint {
        static let login = URL(string: "https://passport2.chaoxing.com/fanyalogin")!
        static let userInfo = URL(string: "https://sso.chaoxing.com/apis/login/userLogin4Uname.do")!
        static let courses = URL(string: "https://mooc1-api.chaoxing.com/mycourse/backclazzdata?view=json&rss=1")!
        static let activities = URL(string: "https://mobilelearn.chaoxing.com/v2/apis/active/student/activelist?fid=0&showNotStartedActive=0")!
        static let signInfo = URL(string: "https://mobilelearn.chaoxing.com/v2/apis/active/getPPTActiveInfo")!
        static let preSign = URL(string: "https://mobilelearn.chaoxing.com/newsign/preSign")!
        static let analysis = URL(string: "https://mobilelearn.chaoxing.com/pptSign/analysis?vs=1&DB_STRATEGY=RANDOM")!
        static let analysis2 = URL(string: "https://mobilelearn.chaoxing.com/pptSign/analysis2?DB_STRATEGY=RANDOM")!
        static let ordinarySign = URL(string: "https://mobilelearn.chaoxing.com/pptSign/stuSignajax")!
        static let checkGesture = URL(string: "https://mobilelearn.chaoxing.com/widget/sign/pcStuSignController/checkSignCode")!
        static let signDetail = URL(string: "https://mobilelearn.chaoxing.com/newsign/signDetail")!
        static let cloudToken = URL(string: "https://pan-yz.chaoxing.com/api/token/uservalid")!
        static let cloudUpload = URL(string: "https://pan-yz.chaoxing.com/upload")!
    }

    private let http: HTTPClient
    private(set) var session: ChaoxingSession?
    private var cachedCloudToken: String?

    init(http: HTTPClient? = nil) {
        self.http = http ?? HTTPClient()
    }

    var authenticationCookies: [HTTPCookie] {
        http.chaoxingCookies
    }

    func restore(_ persistedSession: ChaoxingSession, cookies: [HTTPCookie]) {
        session = persistedSession
        http.restore(cookies: cookies)
    }

    func login(phoneNumber: String, password: String) async throws -> ChaoxingSession {
        let phoneNumber = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phoneNumber.isEmpty else {
            throw ChaoxingError.invalidInput("请输入手机号或账号")
        }
        guard (8...16).contains(password.count) else {
            throw ChaoxingError.invalidInput("密码长度应为 8–16 位")
        }

        http.clearChaoxingCookies()
        cachedCloudToken = nil
        let encryptedUser = try ChaoxingCrypto.encryptLoginValue(phoneNumber)
        let encryptedPassword = try ChaoxingCrypto.encryptLoginValue(password)
        let response = try await http.send(
            Endpoint.login,
            method: "POST",
            form: [
                ("fid", "-1"),
                ("uname", encryptedUser),
                ("password", encryptedPassword),
                ("refer", "https://i.chaoxing.com"),
                ("t", "true"),
                ("forbidotherlogin", "0"),
                ("validate", ""),
                ("doubleFactorLogin", "0"),
                ("independentId", "0"),
                ("independentNameId", "0")
            ]
        )
        let loginPayload = try JSONReader.object(from: response.data)
        guard loginPayload.boolean("status") == true else {
            throw ChaoxingError.invalidInput(loginPayload.string("msg2") ?? "登录失败")
        }

        let userResponse = try await http.send(Endpoint.userInfo)
        let user = try ChaoxingParsers.user(from: userResponse.data, phoneNumber: phoneNumber)
        let newSession = ChaoxingSession(
            user: user,
            configuredFID: user.defaultFID,
            deviceCode: DeviceCodeStore.loadOrCreate()
        )
        session = newSession
        return newSession
    }

    func logout() {
        session = nil
        cachedCloudToken = nil
        http.clearChaoxingCookies()
    }

    func uploadFacePhoto(_ jpegData: Data) async throws -> String {
        try await uploadPhoto(jpegData, session: requireSession())
    }

    func courses() async throws -> [ChaoxingCourse] {
        _ = try requireSession()
        let response = try await http.send(Endpoint.courses)
        return try ChaoxingParsers.courses(from: response.data)
    }

    func activities(for course: ChaoxingCourse) async throws -> [ChaoxingActivity] {
        _ = try requireSession()
        let response = try await http.send(
            Endpoint.activities,
            query: [
                URLQueryItem(name: "courseId", value: String(course.courseID)),
                URLQueryItem(name: "classId", value: String(course.classID))
            ]
        )
        return try ChaoxingParsers.activities(from: response.data, course: course)
    }

    func prepareOrdinarySign(_ activity: ChaoxingActivity) async throws -> OrdinarySignPreparation {
        switch try await prepareOrdinaryOrPhotoSign(activity) {
        case .ready(isPhotoRequired: false): return .ready
        case .ready(isPhotoRequired: true):
            throw ChaoxingError.unsupportedSign("该活动要求上传照片")
        case .alreadySigned: return .alreadySigned
        case .expired: return .expired
        }
    }

    func prepareOrdinaryOrPhotoSign(_ activity: ChaoxingActivity) async throws -> OrdinaryOrPhotoSignPreparation {
        let current = try requireSession()
        guard activity.kind == .ordinaryOrPhoto else {
            throw ChaoxingError.unsupportedSign("该活动不是普通或拍照签到")
        }

        let response = try await http.send(
            preSignURL(activity: activity, session: current),
            method: "POST",
            form: [("ext", activity.ext)]
        )
        if response.text.contains("校验失败，未查询到活动数据") {
            throw ChaoxingError.notInClass
        }
        try await postAnalysis(activeID: activity.id)

        let info = try await signInfo(activeID: activity.id)
        let isPhotoRequired = info.integer("ifphoto") == 1
        if isExpired(response.text) { return .expired(isPhotoRequired: isPhotoRequired) }
        if isAlreadySigned(response.text) { return .alreadySigned(isPhotoRequired: isPhotoRequired) }

        guard info.integer("openCheckFaceFlag") != 1 else {
            throw ChaoxingError.unsupportedSign("该活动要求人脸识别，当前版本暂未接入")
        }
        guard info.integer("ifopenAddress") != 1 else {
            throw ChaoxingError.unsupportedSign("该活动要求位置信息，当前版本暂未接入")
        }
        guard info.integer("ifNeedVCode") != 1 else {
            throw ChaoxingError.captchaRequired
        }
        return .ready(isPhotoRequired: isPhotoRequired)
    }

    func signOrdinary(_ activity: ChaoxingActivity) async throws -> OrdinarySignResult {
        let current = try requireSession()
        return try await submitSign(activity, session: current, objectID: nil)
    }

    func signPhoto(_ activity: ChaoxingActivity, jpegData: Data) async throws -> OrdinarySignResult {
        let current = try requireSession()
        guard !jpegData.isEmpty else {
            throw ChaoxingError.invalidInput("照片数据为空")
        }
        let objectID = try await uploadPhoto(jpegData, session: current)
        return try await submitSign(activity, session: current, objectID: objectID)
    }

    func prepareGestureSign(_ activity: ChaoxingActivity) async throws -> GestureSignPreparation {
        let current = try requireSession()
        guard activity.kind == .gesture else {
            throw ChaoxingError.unsupportedSign("该活动不是手势签到")
        }

        let response = try await http.send(
            preSignURL(activity: activity, session: current),
            method: "POST",
            form: [("ext", activity.ext)]
        )
        if response.text.contains("校验失败，未查询到活动数据") {
            throw ChaoxingError.notInClass
        }
        try await postAnalysis(activeID: activity.id)

        let info = try await signInfo(activeID: activity.id)
        let isLocationRequired = info.integer("ifopenAddress") == 1
        if isExpired(response.text) { return .expired(isLocationRequired: isLocationRequired) }
        if isAlreadySigned(response.text) {
            return .alreadySigned(isLocationRequired: isLocationRequired)
        }

        guard info.integer("openCheckFaceFlag") != 1 else {
            throw ChaoxingError.unsupportedSign("该活动要求人脸识别，当前版本暂未接入")
        }
        guard info.integer("ifNeedVCode") != 1 else {
            throw ChaoxingError.captchaRequired
        }
        return .ready(isLocationRequired: isLocationRequired)
    }

    func checkGestureSignCode(_ code: String, for activity: ChaoxingActivity) async throws -> Bool {
        _ = try requireSession()
        guard activity.kind == .gesture else {
            throw ChaoxingError.unsupportedSign("该活动不是手势签到")
        }
        guard !code.isEmpty, code.allSatisfy({ ("1"..."9").contains(String($0)) }) else {
            throw ChaoxingError.invalidInput("手势图案无效")
        }

        let response = try await http.send(
            Endpoint.checkGesture,
            query: [
                URLQueryItem(name: "activeId", value: String(activity.id)),
                URLQueryItem(name: "signCode", value: code)
            ]
        )
        return try JSONReader.object(from: response.data).integer("result") == 1
    }

    func signGesture(
        _ activity: ChaoxingActivity,
        code: String,
        location: ChaoxingSignLocation?
    ) async throws -> OrdinarySignResult {
        let current = try requireSession()
        guard activity.kind == .gesture else {
            throw ChaoxingError.unsupportedSign("该活动不是手势签到")
        }
        guard !code.isEmpty else {
            throw ChaoxingError.invalidInput("请先绘制手势图案")
        }

        var query = [
            URLQueryItem(name: "activeId", value: String(activity.id)),
            URLQueryItem(name: "courseId", value: String(activity.course.courseID)),
            URLQueryItem(name: "uid", value: String(current.user.puid)),
            URLQueryItem(name: "clientip", value: ""),
            URLQueryItem(name: "latitude", value: location.map { coordinateString($0.bd09Latitude) } ?? "-1"),
            URLQueryItem(name: "longitude", value: location.map { coordinateString($0.bd09Longitude) } ?? "-1"),
            URLQueryItem(name: "appType", value: "15"),
            URLQueryItem(name: "fid", value: String(current.configuredFID)),
            URLQueryItem(name: "name", value: current.user.name),
            URLQueryItem(name: "signCode", value: code),
            URLQueryItem(name: "deviceCode", value: current.deviceCode)
        ]
        if let location {
            query.append(
                URLQueryItem(
                    name: "location",
                    value: try locationJSON(location, includesMockData: false)
                )
            )
            query.append(
                URLQueryItem(
                    name: "locationResult",
                    value: try locationJSON(location, includesMockData: true)
                )
            )
        }
        let response = try await http.send(Endpoint.ordinarySign, query: query)
        return try parseSignResponse(response.text)
    }

    func prepareCodeSign(_ activity: ChaoxingActivity) async throws -> CodeSignPreparation {
        let current = try requireSession()
        guard activity.kind == .password || activity.kind == .qrCode else {
            throw ChaoxingError.unsupportedSign("该活动不是签到码或二维码签到")
        }
        let response = try await http.send(
            preSignURL(activity: activity, session: current),
            method: "POST",
            form: [("ext", activity.ext)]
        )
        if response.text.contains("校验失败，未查询到活动数据") {
            throw ChaoxingError.notInClass
        }
        try await postAnalysis(activeID: activity.id)
        let info = try await signInfo(activeID: activity.id)
        if isExpired(response.text) { return .expired }
        if isAlreadySigned(response.text) { return .alreadySigned }
        guard info.integer("openCheckFaceFlag") != 1 else {
            throw ChaoxingError.unsupportedSign("该活动要求人脸识别，当前版本暂未接入")
        }
        guard info.integer("ifNeedVCode") != 1 else {
            throw ChaoxingError.captchaRequired
        }
        return .ready(
            isLocationRequired: info.integer("ifopenAddress") == 1,
            codeLength: activity.kind == .password ? info.integer("numberCount") : nil,
            isRefreshingQR: info.integer("ifrefreshewm") == 1
        )
    }

    func checkPassword(_ code: String, for activity: ChaoxingActivity) async throws -> Bool {
        guard activity.kind == .password, !code.isEmpty, code.allSatisfy(\.isNumber) else {
            throw ChaoxingError.invalidInput("签到码无效")
        }
        let response = try await http.send(Endpoint.checkGesture, query: [
            URLQueryItem(name: "activeId", value: String(activity.id)),
            URLQueryItem(name: "signCode", value: code)
        ])
        return try JSONReader.object(from: response.data).integer("result") == 1
    }

    func checkQRCode(_ code: ParsedSignQRCode, for activity: ChaoxingActivity) async throws -> Bool {
        guard activity.kind == .qrCode, code.activeID == nil || code.activeID == activity.id else {
            throw ChaoxingError.invalidInput("二维码与当前活动不匹配")
        }
        guard let signCode = code.code else { return true }
        let response = try await http.send(Endpoint.signDetail, query: [
            URLQueryItem(name: "activePrimaryId", value: String(activity.id)),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "msg", value: signCode)
        ])
        let detail = try JSONReader.object(from: response.data)
        return detail.integer("isOver") != 1 && detail.string("signCode") == signCode
    }

    func signCode(
        _ activity: ChaoxingActivity,
        code: String?,
        qrCode: ParsedSignQRCode?,
        location: ChaoxingSignLocation?
    ) async throws -> OrdinarySignResult {
        let current = try requireSession()
        guard activity.kind == .password || activity.kind == .qrCode else {
            throw ChaoxingError.unsupportedSign("签到类型无效")
        }
        var query = [
            URLQueryItem(name: "activeId", value: String(activity.id)),
            URLQueryItem(name: "courseId", value: String(activity.course.courseID)),
            URLQueryItem(name: "uid", value: String(current.user.puid)),
            URLQueryItem(name: "clientip", value: ""),
            URLQueryItem(name: "latitude", value: activity.kind == .qrCode ? "-1" : location.map { coordinateString($0.bd09Latitude) } ?? "-1"),
            URLQueryItem(name: "longitude", value: activity.kind == .qrCode ? "-1" : location.map { coordinateString($0.bd09Longitude) } ?? "-1"),
            URLQueryItem(name: "appType", value: "15"),
            URLQueryItem(name: "fid", value: String(current.configuredFID)),
            URLQueryItem(name: "name", value: current.user.name),
            URLQueryItem(name: "deviceCode", value: current.deviceCode)
        ]
        if activity.kind == .password {
            guard let code, !code.isEmpty else { throw ChaoxingError.invalidInput("请输入签到码") }
            query.append(URLQueryItem(name: "signCode", value: code))
        } else {
            guard let qrCode else { throw ChaoxingError.invalidInput("请扫描签到二维码") }
            guard try await checkQRCode(qrCode, for: activity) else {
                throw ChaoxingError.invalidInput("二维码已过期，请重新扫描")
            }
            query.append(URLQueryItem(name: "enc", value: qrCode.enc))
            query.append(URLQueryItem(name: "vpProbability", value: "-1"))
            query.append(URLQueryItem(name: "vpStrategy", value: ""))
        }
        if let location {
            query.append(URLQueryItem(name: "location", value: try locationJSON(location, includesMockData: false)))
            query.append(URLQueryItem(name: "locationResult", value: try locationJSON(location, includesMockData: true)))
        }
        let response = try await http.send(Endpoint.ordinarySign, query: query)
        return try parseSignResponse(response.text)
    }

    func prepareLocationSign(_ activity: ChaoxingActivity) async throws -> LocationSignPreparation {
        let current = try requireSession()
        guard activity.kind == .location else {
            throw ChaoxingError.unsupportedSign("该活动不是位置签到")
        }

        let response = try await http.send(
            preSignURL(activity: activity, session: current),
            method: "POST",
            form: [("ext", activity.ext)]
        )
        if response.text.contains("校验失败，未查询到活动数据") {
            throw ChaoxingError.notInClass
        }
        try await postAnalysis(activeID: activity.id)

        let info = try await signInfo(activeID: activity.id)
        let detail = LocationSignDetail(
            bd09Latitude: info.double("locationLatitude"),
            bd09Longitude: info.double("locationLongitude"),
            range: info.integer("locationRange")
        )
        if isExpired(response.text) { return .expired(detail) }
        if isAlreadySigned(response.text) { return .alreadySigned(detail) }

        guard info.integer("openCheckFaceFlag") != 1 else {
            throw ChaoxingError.unsupportedSign("该活动要求人脸识别，当前版本暂未接入")
        }
        guard info.integer("ifNeedVCode") != 1 else {
            throw ChaoxingError.captchaRequired
        }
        return .ready(detail)
    }

    func signLocation(
        _ activity: ChaoxingActivity,
        location: ChaoxingSignLocation
    ) async throws -> OrdinarySignResult {
        let current = try requireSession()
        guard activity.kind == .location else {
            throw ChaoxingError.unsupportedSign("该活动不是位置签到")
        }

        // One rounded BD-09 pair for both representations; no extra conversion/jitter.
        let latitude = location.bd09Latitude
        let longitude = location.bd09Longitude
        let locationResult = try locationJSON(location, includesMockData: true)
        let response = try await http.send(
            Endpoint.ordinarySign,
            query: [
                URLQueryItem(name: "name", value: current.user.name),
                URLQueryItem(name: "address", value: location.address),
                URLQueryItem(name: "activeId", value: String(activity.id)),
                URLQueryItem(name: "courseId", value: String(activity.course.courseID)),
                URLQueryItem(name: "uid", value: String(current.user.puid)),
                URLQueryItem(name: "clientip", value: ""),
                URLQueryItem(name: "latitude", value: String(latitude)),
                URLQueryItem(name: "longitude", value: String(longitude)),
                URLQueryItem(name: "fid", value: String(current.configuredFID)),
                URLQueryItem(name: "appType", value: "15"),
                URLQueryItem(name: "ifTiJiao", value: "1"),
                URLQueryItem(name: "deviceCode", value: current.deviceCode),
                URLQueryItem(name: "vpProbability", value: "-1"),
                URLQueryItem(name: "vpStrategy", value: ""),
                URLQueryItem(name: "locationResult", value: locationResult)
            ]
        )
        return try parseSignResponse(response.text)
    }

    private func submitSign(
        _ activity: ChaoxingActivity,
        session current: ChaoxingSession,
        objectID: String?
    ) async throws -> OrdinarySignResult {
        var query = [
            URLQueryItem(name: "activeId", value: String(activity.id)),
            URLQueryItem(name: "courseId", value: String(activity.course.courseID)),
            URLQueryItem(name: "uid", value: String(current.user.puid)),
            URLQueryItem(name: "clientip", value: ""),
            URLQueryItem(name: "useragent", value: ""),
            URLQueryItem(name: "latitude", value: "-1"),
            URLQueryItem(name: "longitude", value: "-1"),
            URLQueryItem(name: "appType", value: "15"),
            URLQueryItem(name: "fid", value: String(current.configuredFID)),
            URLQueryItem(name: "name", value: current.user.name),
            URLQueryItem(name: "deviceCode", value: current.deviceCode)
        ]
        if let objectID {
            query.append(URLQueryItem(name: "objectId", value: objectID))
        }
        let response = try await http.send(
            Endpoint.ordinarySign,
            query: query
        )
        return try parseSignResponse(response.text)
    }

    private func parseSignResponse(_ responseText: String) throws -> OrdinarySignResult {
        switch responseText.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "success":
            return .success
        case "success2":
            throw ChaoxingError.signExpired
        case "您已签到过了":
            throw ChaoxingError.alreadySigned
        case let value where value.hasPrefix("validate"):
            throw ChaoxingError.captchaRequired
        case let value where value.hasPrefix("checkFace_"):
            throw ChaoxingError.unsupportedSign("该活动要求人脸识别，当前版本暂未接入")
        case let value where value.hasPrefix("errorLocation"):
            let distance = value.split(separator: "_").dropFirst().first.flatMap { Double($0) }
            throw ChaoxingError.outsideLocationRange(distance)
        case let value where value.contains("同一设备不允许重复签到"):
            throw ChaoxingError.signFailed("同一设备不允许重复签到")
        case let value:
            throw ChaoxingError.signFailed(value.isEmpty ? "签到失败" : value)
        }
    }

    private func locationJSON(
        _ location: ChaoxingSignLocation,
        includesMockData: Bool
    ) throws -> String {
        var payload: [String: Any] = [
            "result": 1,
            "latitude": location.bd09Latitude,
            "longitude": location.bd09Longitude,
            "address": location.address
        ]
        if includesMockData {
            payload["mockData"] = #"{"strategy":0,"probability":-1}"#
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ChaoxingError.invalidResponse("无法生成位置签到参数")
        }
        return json
    }

    private func coordinateString(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func uploadPhoto(_ jpegData: Data, session: ChaoxingSession) async throws -> String {
        let token: String
        if let cachedCloudToken {
            token = cachedCloudToken
        } else {
            let tokenResponse = try await http.send(Endpoint.cloudToken)
            let payload = try JSONReader.object(from: tokenResponse.data)
            guard let value = payload.string("_token"), !value.isEmpty else {
                throw ChaoxingError.invalidResponse("无法获取图片上传凭证")
            }
            cachedCloudToken = value
            token = value
        }

        var components = URLComponents(url: Endpoint.cloudUpload, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "_from", value: "mobilelearn"),
            URLQueryItem(name: "_token", value: token)
        ]
        guard let uploadURL = components.url else {
            throw ChaoxingError.invalidInput("图片上传地址无效")
        }
        let response = try await http.sendMultipart(
            uploadURL,
            fields: [("puid", String(session.user.puid))],
            fileField: "file",
            filename: "\(UUID().uuidString).jpg",
            mimeType: "image/jpeg",
            fileData: jpegData
        )
        let payload = try JSONReader.object(from: response.data)
        guard let objectID = payload.string("objectId"), !objectID.isEmpty else {
            throw ChaoxingError.invalidResponse(payload.string("msg") ?? "图片上传失败")
        }
        return objectID
    }

    private func requireSession() throws -> ChaoxingSession {
        guard let session else { throw ChaoxingError.sessionExpired }
        return session
    }

    private func signInfo(activeID: Int64) async throws -> JSONObject {
        let response = try await http.send(
            Endpoint.signInfo,
            query: [URLQueryItem(name: "activeId", value: String(activeID))]
        )
        let root = try JSONReader.object(from: response.data)
        guard let info = root.object("data") else {
            throw ChaoxingError.invalidResponse(root.string("errorMsg") ?? "无法获取签到详情")
        }
        return info
    }

    private func preSignURL(activity: ChaoxingActivity, session: ChaoxingSession) -> URL {
        var components = URLComponents(url: Endpoint.preSign, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "courseId", value: String(activity.course.courseID)),
            URLQueryItem(name: "classId", value: String(activity.course.classID)),
            URLQueryItem(name: "activePrimaryId", value: String(activity.id)),
            URLQueryItem(name: "general", value: "1"),
            URLQueryItem(name: "sys", value: "1"),
            URLQueryItem(name: "ls", value: "1"),
            URLQueryItem(name: "appType", value: "15"),
            URLQueryItem(name: "uid", value: String(session.user.puid)),
            URLQueryItem(name: "isTeacherViewOpen", value: "0")
        ]
        return components.url!
    }

    private func postAnalysis(activeID: Int64) async throws {
        let response = try await http.send(
            Endpoint.analysis,
            query: [URLQueryItem(name: "aid", value: String(activeID))]
        )
        let regex = try NSRegularExpression(pattern: #"code\s*=\s*'\+'([A-Fa-f0-9]+)'"#)
        let range = NSRange(response.text.startIndex..., in: response.text)
        guard let match = regex.firstMatch(in: response.text, range: range),
              let codeRange = Range(match.range(at: 1), in: response.text) else {
            throw ChaoxingError.invalidResponse("签到预处理失败：服务器未返回分析码")
        }
        _ = try await http.send(
            Endpoint.analysis2,
            query: [URLQueryItem(name: "code", value: String(response.text[codeRange]))]
        )
    }

    private func isAlreadySigned(_ html: String) -> Bool {
        let patterns = [
            #"\"primaryAttend\"\s*:\s*\{[^{}]*?\"status\"\s*:\s*(\d+)"#,
            #"signstatus\s*=\s*(\d+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html),
                  let status = Int(html[range]) else { continue }
            return [1, 2, 3, 9].contains(status)
        }
        return false
    }

    private func isExpired(_ html: String) -> Bool {
        html.contains("下次早点哦")
    }
}
