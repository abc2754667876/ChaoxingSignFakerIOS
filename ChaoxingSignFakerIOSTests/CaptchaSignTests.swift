import CoreLocation
import Foundation
import Testing
@testable import ChaoxingSignFakerIOS

@MainActor
struct CaptchaSignTests {
    @Test(arguments: ["ordinary", "photo", "location", "gesture", "password", "qr"])
    func supportsCaptchaAcrossSignKindsAndPreservesParameters(_ kind: String) async throws {
        let (api, fixture) = makeAPI(kind == "photo" ? "photo" : "normal")
        let activity = activity(kind)
        switch kind {
        case "ordinary", "photo": _ = try await api.prepareOrdinaryOrPhotoSign(activity)
        case "location": _ = try await api.prepareLocationSign(activity)
        case "gesture": _ = try await api.prepareGestureSign(activity)
        default: _ = try await api.prepareCodeSign(activity)
        }
        api.captchaProvider = { api, activity in
            let challenge = try await api.captcha(for: activity)
            #expect(challenge.token == "server-token")
            return try #require(try await api.checkCaptcha(challenge, progress: 0.5, for: activity))
        }
        let originalLocation = ChaoxingSignLocation(address: "Test", wgs84Coordinate: CLLocationCoordinate2D(latitude: 30, longitude: 120))
        let location = kind == "location" ? originalLocation.randomizedWithinSevenMeters() : originalLocation
        let result: OrdinarySignResult
        switch kind {
        case "photo": result = try await api.signPhoto(activity, jpegData: Data([1, 2, 3]))
        case "location": result = try await api.signLocation(activity, location: location)
        case "gesture": result = try await api.signGesture(activity, code: "123", location: location)
        case "password": result = try await api.signCode(activity, code: "1234", qrCode: nil, location: location)
        case "qr": result = try await api.signCode(activity, code: nil, qrCode: qrCode(), location: location)
        default: result = try await api.signOrdinary(activity)
        }
        #expect(result == .success)
        let submissions = fixture.requests("stuSignajax")
        #expect(submissions.count == 2)
        let original = query(try #require(submissions.first))
        let retried = query(try #require(submissions.last))
        for (key, value) in original { #expect(retried[key] == value) }
        #expect(retried["validate"] == "validated-1")
        #expect(retried["enc2"] == "captcha-enc")
        if kind == "location" {
            #expect(Double(try #require(original["latitude"])) == location.bd09Latitude)
            #expect(Double(try #require(original["longitude"])) == location.bd09Longitude)
            let data = Data(try #require(original["locationResult"]).utf8)
            let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(payload["latitude"] as? Double == location.bd09Latitude)
            #expect(payload["longitude"] as? Double == location.bd09Longitude)
        }
        #expect(fixture.requests("upload").count == (kind == "photo" ? 1 : 0))
        let image = query(try #require(fixture.requests("image").first))
        #expect(image["token"] == ChaoxingCrypto.md5("1700000000000Qt9FIw9o4pwRjOyqM6yizZBh682qN2TUslide\(image["captchaKey"] ?? "")") + ":1700000300000")
        let check = query(try #require(fixture.requests("result").first))
        #expect(check["token"] == "server-token")
        #expect(check["textClickArr"] == "[{\"x\":132}]")
        #expect(fixture.requests("result").first?.value(forHTTPHeaderField: "Referer")?.contains("activePrimaryId=123") == true)
    }

    @Test(arguments: ["faceFirst", "captchaFirst", "knownFace"])
    func handlesBothFaceAndCaptchaWithoutSharingRetryBudget(_ scenario: String) async throws {
        let (api, fixture) = makeAPI(scenario)
        var faceCalls = 0
        var captchaCalls = 0
        api.facePhotoProvider = { _, _ in faceCalls += 1; return "face-1" }
        api.captchaProvider = { _, _ in captchaCalls += 1; return "validated-1" }
        #expect(try await api.signOrdinary(activity()) == .success)
        #expect(faceCalls > 0)
        #expect(captchaCalls == 1)
        let final = query(try #require(fixture.requests("stuSignajax").last))
        #expect(final["currentFaceId"] == "face-1")
        #expect(final["faceEnc"] == "face-enc")
        #expect(final["validate"] == "validated-1")
        #expect(final["enc2"] == (scenario == "captchaFirst" ? "face-enc2" : "captcha-enc"))
    }

    @Test func rejectsRotatedQRCodeAfterCaptchaBeforeResubmission() async throws {
        let (api, fixture) = makeAPI("rotatedQR")
        api.captchaProvider = { _, _ in fixture.rotateQR(); return "validated-1" }
        await #expect(throws: ChaoxingError.invalidInput("二维码已过期，请重新扫描")) {
            try await api.signCode(activity("qr"), code: nil, qrCode: qrCode(), location: nil)
        }
        #expect(fixture.requests("stuSignajax").count == 1)
    }

    @Test(arguments: ["cancel", "logout", "leave"])
    func stopsSubmissionWhenContextChangesDuringCaptcha(_ scenario: String) async throws {
        let (api, fixture) = makeAPI()
        var isActive = true
        api.faceSignIsActive = { _ in isActive }
        api.captchaProvider = { api, _ in
            switch scenario {
            case "logout": api.logout()
            case "leave": isActive = false
            default: throw ChaoxingError.signCancelled
            }
            return "validated-1"
        }
        let expected: ChaoxingError = scenario == "logout" ? .sessionExpired : .signCancelled
        await #expect(throws: expected) { try await api.signOrdinary(activity()) }
        #expect(fixture.requests("stuSignajax").count == 1)
    }

    @Test func boundsCaptchaRetries() async throws {
        let (api, fixture) = makeAPI("repeatedCaptcha")
        var prompts = 0
        api.captchaProvider = { _, _ in prompts += 1; return "validated-1" }
        await #expect(throws: ChaoxingError.captchaFailed("验证码凭证未被接受，请重新提交签到")) {
            try await api.signOrdinary(activity())
        }
        #expect(prompts == 2)
        #expect(fixture.requests("stuSignajax").count == 3)
    }

    @Test(arguments: ["invalidSlide", "expiredSlide", "missingValidate", "escapedExtra", "objectExtra", "serviceError"])
    func handlesCaptchaResponses(_ scenario: String) async throws {
        let (api, _) = makeAPI(scenario)
        let challenge = try await api.captcha(for: activity())
        switch scenario {
        case "invalidSlide": #expect(try await api.checkCaptcha(challenge, progress: 0.5, for: activity()) == nil)
        case "escapedExtra", "objectExtra":
            #expect(try await api.checkCaptcha(challenge, progress: 0.5, for: activity()) == "validated-1")
        default:
            do {
                _ = try await api.checkCaptcha(challenge, progress: 0.5, for: activity())
                Issue.record("Invalid captcha was accepted")
            } catch let error as ChaoxingError {
                switch error {
                case .captchaFailed, .invalidResponse: break
                default: Issue.record("Unexpected error: \(error)")
                }
            }
        }
    }

    @Test func parsesJSONPWithoutDamagingStringsAndPreservesEnc2() throws {
        #expect(try ChaoxingAPI.captchaJSON(#"cx_captcha_function({"msg":"(keep)"});"#).string("msg") == "(keep)")
        #expect(throws: (any Error).self) { try ChaoxingAPI.captchaJSON("other({})") }
        let (api, _) = makeAPI()
        #expect(throws: ChaoxingError.captchaRequired(enc2: nil)) { try api.parseSignResponse("validate") }
        #expect(throws: ChaoxingError.captchaRequired(enc2: "a_b")) { try api.parseSignResponse("validate_a_b") }
        #expect(ChaoxingCaptcha.verificationX(progress: 0) == -8)
        #expect(ChaoxingCaptcha.verificationX(progress: 1) == 272)
        #expect(ChaoxingCrypto.md5("abc") == "900150983cd24fb0d6963f7d28e17f72")
    }

    @Test func coordinatorWaitsForDismissalAndIsolatesAccountsAndStaleCallbacks() async throws {
        let coordinator = CaptchaCoordinator()
        coordinator.activate(activityID: 123)
        let (firstAPI, _) = makeAPI(uid: 1)
        let first = Task { try await coordinator.resolve(api: firstAPI, activity: activity()) }
        let firstRequest = try await waitForRequest(coordinator)
        #expect(firstRequest.user.uid == 1)
        coordinator.complete("first-token", requestID: firstRequest.id)
        #expect(coordinator.request == nil)
        coordinator.dismiss(requestID: firstRequest.id)
        #expect(try await first.value == "first-token")
        let (secondAPI, _) = makeAPI(uid: 2)
        let second = Task { try await coordinator.resolve(api: secondAPI, activity: activity()) }
        let secondRequest = try await waitForRequest(coordinator)
        #expect(secondRequest.user.uid == 2)
        coordinator.complete("stale-token", requestID: firstRequest.id)
        coordinator.dismiss(requestID: firstRequest.id)
        #expect(coordinator.request?.id == secondRequest.id)
        coordinator.request = nil
        coordinator.dismiss(requestID: secondRequest.id)
        await #expect(throws: ChaoxingError.signCancelled) { try await second.value }
        let cancelled = Task { try await coordinator.resolve(api: secondAPI, activity: activity()) }
        _ = try await waitForRequest(coordinator)
        cancelled.cancel()
        await #expect(throws: ChaoxingError.signCancelled) { try await cancelled.value }
        #expect(coordinator.request == nil)
        coordinator.resetAll()
    }

    @Test func isolatesCredentialsAcrossAccountAPIs() async throws {
        for uid in [1, 2] {
            let (api, fixture) = makeAPI(uid: uid)
            api.captchaProvider = { api, _ in "validated-\(api.session!.user.uid)" }
            #expect(try await api.signOrdinary(activity()) == .success)
            let final = query(try #require(fixture.requests("stuSignajax").last))
            #expect(final["uid"] == String(uid))
            #expect(final["validate"] == "validated-\(uid)")
        }
    }

    @Test func submitsPredictedOffsetWithoutManualSliderNormalization() async throws {
        let (api, fixture) = makeAPI()
        api.captchaProvider = { api, activity in
            let challenge = try await api.captcha(for: activity)
            let result = try await CaptchaAutomaticResolver.resolve(imageData: Data()) { _ in 136 } verify: { offset in
                try await api.checkCaptcha(challenge, xPosition: offset, for: activity)
            }
            guard case .solved(let validate) = result else {
                throw ChaoxingError.captchaFailed("Automatic verification failed")
            }
            return validate
        }
        #expect(try await api.signOrdinary(activity()) == .success)
        let check = query(try #require(fixture.requests("result").first))
        #expect(check["textClickArr"] == "[{\"x\":136}]")
        let final = query(try #require(fixture.requests("stuSignajax").last))
        #expect(final["validate"] == "validated-1")
        #expect(final["enc2"] == "captcha-enc")
    }

    @Test func rejectsExpiredAndInvalidPositionsWithoutNetworkRequests() async throws {
        let (api, fixture) = makeAPI()
        let original = try await api.captcha(for: activity())
        let expired = ChaoxingCaptcha(captchaID: original.captchaID, type: original.type, version: original.version,
                                      token: original.token, iv: original.iv, shadeImageURL: original.shadeImageURL,
                                      cutoutImageURL: original.cutoutImageURL, expiresAt: .distantPast)
        await #expect(throws: ChaoxingError.captchaFailed("验证码已过期，请刷新")) {
            try await api.checkCaptcha(expired, progress: 0.5, for: activity())
        }
        await #expect(throws: ChaoxingError.invalidInput("滑块位置无效")) {
            try await api.checkCaptcha(original, progress: .nan, for: activity())
        }
        #expect(fixture.requests("result").isEmpty)
    }

    @Test func leavingDuringDismissalCancelsEvenAnAlreadySolvedChallenge() async throws {
        let coordinator = CaptchaCoordinator()
        coordinator.activate(activityID: 123)
        let (api, _) = makeAPI()
        let task = Task { try await coordinator.resolve(api: api, activity: activity()) }
        let request = try await waitForRequest(coordinator)
        coordinator.complete("solved", requestID: request.id)
        coordinator.reset(activityID: 123)
        await #expect(throws: ChaoxingError.signCancelled) { try await task.value }
        coordinator.dismiss(requestID: request.id)
        await #expect(throws: ChaoxingError.signCancelled) {
            try await coordinator.resolve(api: api, activity: activity())
        }
    }

    @Test func taskCancellationAfterSolvingDoesNotResubmit() async throws {
        let (api, fixture) = makeAPI()
        api.captchaProvider = { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return "validated-1"
        }
        let task = Task { try await api.signOrdinary(activity()) }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(fixture.requests("stuSignajax").count == 1)
    }

    private func waitForRequest(_ coordinator: CaptchaCoordinator) async throws -> CaptchaCoordinator.Request {
        for _ in 0..<1000 {
            if let request = coordinator.request { return request }
            await Task.yield()
        }
        return try #require(coordinator.request)
    }

    private func makeAPI(_ scenario: String = "normal", uid: Int = 1) -> (ChaoxingAPI, CaptchaFixture) {
        let fixture = CaptchaFixture(scenario: scenario)
        let id = UUID().uuidString
        CaptchaFixtureProtocol.register(fixture, id: id)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CaptchaFixtureProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Captcha-Fixture": id]
        let cookies = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "captcha-\(id)")
        let api = ChaoxingAPI(http: HTTPClient(cookieStorage: cookies, configuration: configuration))
        var user = ChaoxingUser(uid: uid, puid: uid, defaultFID: 0, name: "Test", phoneNumber: "", avatarURL: nil, schools: [])
        user.clientID = "invalid"
        api.restore(ChaoxingSession(user: user, configuredFID: 0, deviceCode: "device-\(uid)"), cookies: [])
        return (api, fixture)
    }

    private func qrCode() throws -> ParsedSignQRCode { try ParsedSignQRCode("SIGNIN:id=123&c=1234&enc=qr-token") }

    private func query(_ request: URLRequest) -> [String: String] {
        request.testParameters
    }

    private func activity(_ kind: String = "ordinary") -> ChaoxingActivity {
        let course = ChaoxingCourse(courseName: "Test", teacherName: nil, courseID: 1, classID: 2, className: "Test", imageURL: nil, schoolName: nil)
        return ChaoxingActivity(id: 123, startTime: .now, endTime: nil, userStatus: 0,
                                otherID: ["location": "4", "gesture": "3", "password": "5", "qr": "2"][kind] ?? "0",
                                isLook: false, type: 2, activeType: 2, title: "Test", status: 1, endTimeDescription: "", course: course, ext: "")
    }
}

private final class CaptchaFixture: @unchecked Sendable {
    let scenario: String
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var isRotated = false

    init(scenario: String) { self.scenario = scenario }
    func requests(_ path: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded.filter { $0.url?.lastPathComponent == path }
    }
    func rotateQR() { lock.lock(); defer { lock.unlock() }; isRotated = true }

    func response(_ request: URLRequest) -> String {
        lock.lock(); defer { lock.unlock() }
        let request = request.capturedForTesting
        recorded.append(request)
        let query = request.testParameters
        let path = request.url!.lastPathComponent
        switch path {
        case "analysis": return "code='+'abcdef'"
        case "getPPTActiveInfo": return "{\"data\":{\"ifNeedVCode\":1,\"ifphoto\":\(scenario == "photo" ? 1 : 0),\"openCheckFaceFlag\":\(scenario == "knownFace" ? 1 : 0),\"ifrefreshewm\":1}}"
        case "uservalid": return #"{"_token":"upload-token"}"#
        case "upload": return #"{"objectId":"attendance-photo"}"#
        case "check-face-result": return #"{"enc":"face-enc"}"#
        case "signDetail": return "{\"isOver\":0,\"signCode\":\"\(isRotated ? "5678" : "1234")\"}"
        case "conf": return #"cx_captcha_function({"t":1700000000000})"#
        case "image": return #"cx_captcha_function({"token":"server-token","imageVerificationVo":{"shadeImage":"https://captcha.chaoxing.com/shade.png","cutoutImage":"https://captcha.chaoxing.com/cutout.png"}})"#
        case "result":
            if scenario == "invalidSlide" { return #"cx_captcha_function({"result":false})"# }
            if scenario == "serviceError" || scenario == "expiredSlide" { return #"cx_captcha_function({"error":1,"msg":"expired"})"# }
            if scenario == "missingValidate" { return #"cx_captcha_function({"result":true,"extraData":"{}"})"# }
            if scenario == "objectExtra" { return #"cx_captcha_function({"result":true,"extraData":{"validate":"validated-1"}})"# }
            if scenario == "escapedExtra" { return #"cx_captcha_function({"result":true,"extraData":"{\\\"validate\\\":\\\"validated-1\\\"}"})"# }
            return #"cx_captcha_function({"result":true,"extraData":"{\"validate\":\"validated-1\"}"})"#
        case "stuSignajax":
            guard request.httpMethod == "POST",
                  request.url?.query == nil,
                  request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest",
                  request.value(forHTTPHeaderField: "Referer")?.hasPrefix("https://mobilelearn.chaoxing.com/newsign/preSign?") == true,
                  request.url?.host == "data-xxt.aichaoxing.com",
                  request.value(forHTTPHeaderField: "Host") == "mobilelearn.chaoxing.com" else {
                return "签到环境异常"
            }
            let count = recorded.filter { $0.url?.lastPathComponent == path }.count
            if scenario == "repeatedCaptcha" { return "validate_captcha-enc" }
            if scenario == "faceFirst", query["currentFaceId"] == nil { return "checkFace_face-enc2" }
            if query["validate"] == nil { return "validate_captcha-enc" }
            if scenario == "captchaFirst", query["currentFaceId"] == nil { return "checkFace_face-enc2" }
            guard count >= 2, query["validate"] == "validated-\(query["uid"] ?? "")", query["enc2"] != nil else { return "invalid credentials" }
            return "success"
        default: return "{}"
        }
    }
}

private final class CaptchaFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: CaptchaFixture] = [:]
    static func register(_ fixture: CaptchaFixture, id: String) {
        lock.lock(); defer { lock.unlock() }; fixtures[id] = fixture
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let fixture = Self.fixtures[request.value(forHTTPHeaderField: "X-Captcha-Fixture") ?? ""]
        Self.lock.unlock()
        let body = fixture?.response(request) ?? "{}"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
