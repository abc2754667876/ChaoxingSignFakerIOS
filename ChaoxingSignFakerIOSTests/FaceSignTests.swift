import CoreLocation
import Foundation
import Security
import Testing
@testable import ChaoxingSignFakerIOS

@MainActor
struct FaceSignTests {
    @Test(arguments: ["ordinary", "photo", "location", "gesture", "password", "qr"])
    func addsFaceVerificationToEverySignKind(_ kind: String) async throws {
        let api = makeAPI(kind)
        let activity = activity(kind)
        switch kind {
        case "ordinary", "photo": _ = try await api.prepareOrdinaryOrPhotoSign(activity)
        case "location": _ = try await api.prepareLocationSign(activity)
        case "gesture": _ = try await api.prepareGestureSign(activity)
        default: _ = try await api.prepareCodeSign(activity)
        }
        var requestedUID: Int?
        var acceptedUID: Int?
        api.facePhotoProvider = { api, _ in
            requestedUID = api.session?.user.uid
            return "face-\(requestedUID!)"
        }
        api.facePhotoAccepted = { _, uid in acceptedUID = uid }
        let location = ChaoxingSignLocation(address: "Test", wgs84Coordinate: CLLocationCoordinate2D(latitude: 30, longitude: 120))
        let result: OrdinarySignResult
        switch kind {
        case "photo": result = try await api.signPhoto(activity, jpegData: Data([1, 2, 3]))
        case "location": result = try await api.signLocation(activity, location: location)
        case "gesture": result = try await api.signGesture(activity, code: "123", location: location)
        case "password": result = try await api.signCode(activity, code: "1234", qrCode: nil, location: location)
        case "qr": result = try await api.signCode(activity, code: nil, qrCode: ParsedSignQRCode("SIGNIN:id=123&enc=qr-token&c=1234"), location: location)
        default: result = try await api.signOrdinary(activity)
        }
        #expect(result == .success)
        #expect(requestedUID == 1)
        #expect(acceptedUID == 1)
    }

    @Test func handlesUnexpectedFaceChallengeAndPreservesEnc2() async throws {
        let api = makeAPI("challenge")
        var calls = 0
        api.facePhotoProvider = { _, _ in calls += 1; return "face-1" }
        #expect(try await api.signOrdinary(activity("ordinary")) == .success)
        #expect(calls == 1)
    }

    @Test(arguments: ["badFace", "missingFaceEnc", "repeatedChallenge"])
    func rejectsFaceFailuresAndInvalidatesSelection(_ scenario: String) async throws {
        let api = makeAPI(scenario)
        api.facePhotoProvider = { _, _ in "face-1" }
        var rejectedUID: Int?
        api.facePhotoRejected = { _, uid in rejectedUID = uid }
        do {
            _ = try await api.signOrdinary(activity("ordinary"))
            Issue.record("Face failure was accepted")
        } catch let error as ChaoxingError {
            guard case .faceFailed = error else { Issue.record("Unexpected error: \(error)"); return }
        }
        #expect(rejectedUID == 1)
    }

    @Test func keepsPhotosAndCredentialsSeparateForEachAccount() async throws {
        for uid in [1, 2] {
            let api = makeAPI("ordinary", uid: uid)
            api.facePhotoProvider = { api, _ in "face-\(api.session!.user.uid)" }
            #expect(try await api.signOrdinary(activity("ordinary")) == .success)
        }
    }

    @Test func cancellationPreventsSubmission() async throws {
        let api = makeAPI("ordinary")
        api.facePhotoProvider = { _, _ in throw ChaoxingError.signCancelled }
        await #expect(throws: ChaoxingError.signCancelled) {
            try await api.signOrdinary(activity("ordinary"))
        }
    }

    @Test func loadsDeviceIdentityForExistingSessions() async throws {
        let api = makeAPI("legacy", clientID: nil)
        api.facePhotoProvider = { _, _ in "face-1" }
        #expect(try await api.signOrdinary(activity("ordinary")) == .success)
        #expect(api.session?.user.clientID == "invalid")
    }

    @Test func leavesNonFaceSignsAlone() async throws {
        let api = makeAPI("noFace")
        api.facePhotoProvider = { _, _ in Issue.record("Unexpected face selection"); return "" }
        #expect(try await api.signOrdinary(activity("ordinary")) == .success)
    }

    @Test func checksQRCodeAgainAfterPhotoSelection() async throws {
        let api = makeAPI("qrRotated")
        api.facePhotoProvider = { _, _ in "face-1" }
        // The fixture changes the detail response after the face credential request.
        await #expect(throws: ChaoxingError.invalidInput("二维码已过期，请重新扫描")) {
            try await api.signCode(activity("qr"), code: nil,
                                   qrCode: ParsedSignQRCode("SIGNIN:id=123&c=1234&enc=qr-token"), location: nil)
        }
    }

    @Test func decodesPublicRSAClientIdentityAcrossMultipleBlocks() throws {
        let privateKey = try #require(SecKeyCreateRandomKey([
            kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 1024
        ] as CFDictionary, nil))
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
        let keyData = try #require(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
        let plain = Data(#"{"cid":"device","sc":"secret","extra":"abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"}"#.utf8)
        var signed = Data()
        for offset in stride(from: 0, to: plain.count, by: 100) {
            let block = plain.subdata(in: offset..<min(offset + 100, plain.count))
            signed.append(try #require(SecKeyCreateSignature(privateKey, .rsaSignatureDigestPKCS1v15Raw, block as CFData, nil) as Data?))
        }
        let decoded = try #require(ChaoxingFaceSignature.decodeClientID(signed.base64EncodedString(), keyData: keyData))
        #expect(decoded.string("cid") == "device")
        #expect(decoded.string("sc") == "secret")
        #expect(ChaoxingFaceSignature.decodeClientID("invalid") == nil)
    }

    @Test func networkFailureDoesNotMarkThePhotoAsRejected() async throws {
        let api = makeAPI("networkFace")
        api.facePhotoProvider = { _, _ in "face-1" }
        var rejected = false
        api.facePhotoRejected = { _, _ in rejected = true }
        await #expect(throws: ChaoxingError.server("网络请求失败（HTTP 500）")) {
            try await api.signOrdinary(activity("ordinary"))
        }
        #expect(!rejected)
    }

    @Test func leavingTheSignScreenPreventsSubmission() async throws {
        let api = makeAPI("ordinary")
        api.facePhotoProvider = { _, _ in "face-1" }
        api.faceSignIsActive = { _ in false }
        await #expect(throws: ChaoxingError.signCancelled) {
            try await api.signOrdinary(activity("ordinary"))
        }
    }

    @Test func readsPhotosSavedBeforeFaceSupportWasAdded() throws {
        let legacy = Data(#"{"id":"old-face","addedAt":0}"#.utf8)
        let photo = try JSONDecoder().decode(OtherUserFace.self, from: legacy)
        #expect(photo.id == "old-face")
        #expect(photo.useCount == nil)
        #expect(photo.hasFailed == nil)
        let user = try JSONDecoder().decode(ChaoxingUser.self, from: Data(#"{"uid":1,"puid":1,"defaultFID":0,"name":"Test","phoneNumber":"","schools":[]}"#.utf8))
        #expect(user.clientID == nil)
    }

    @Test func coordinatorCompletesOnlyAfterSheetDismissalAndCanCancel() async throws {
        let coordinator = FaceSignCoordinator()
        coordinator.activate(activityID: 123)
        let api = makeAPI("ordinary")
        let task = Task { try await coordinator.select(api: api, activity: activity("ordinary"), currentUID: 1) }
        while coordinator.request == nil { await Task.yield() }
        let id = try #require(coordinator.request?.id)
        coordinator.choose("face-1", requestID: id)
        #expect(coordinator.request == nil)
        coordinator.dismissSelection()
        #expect(try await task.value == "face-1")
        #expect(try await coordinator.select(api: api, activity: activity("ordinary"), currentUID: 1) == "face-1")
        coordinator.finish(activityID: 123, uid: 1, isFailure: true)
        let retry = Task { try await coordinator.select(api: api, activity: activity("ordinary"), currentUID: 1) }
        while coordinator.request == nil { await Task.yield() }
        coordinator.request = nil
        coordinator.dismissSelection()
        await #expect(throws: ChaoxingError.signCancelled) { try await retry.value }
    }

    private func makeAPI(_ scenario: String, uid: Int = 1, clientID: String? = "invalid") -> ChaoxingAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FaceFixtureProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Face-Scenario": scenario, "X-Face-UID": String(uid)]
        let cookies = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "face-test-\(UUID())")
        let api = ChaoxingAPI(http: HTTPClient(cookieStorage: cookies, configuration: configuration))
        var user = ChaoxingUser(uid: uid, puid: uid, defaultFID: 0, name: "Test", phoneNumber: "test-\(uid)", avatarURL: nil, schools: [])
        user.clientID = clientID
        api.restore(ChaoxingSession(user: user, configuredFID: 0, deviceCode: "device-\(uid)"), cookies: [])
        return api
    }

    private func activity(_ kind: String) -> ChaoxingActivity {
        let course = ChaoxingCourse(courseName: "Test", teacherName: nil, courseID: 1, classID: 2,
                                    className: "Test", imageURL: nil, schoolName: nil)
        return ChaoxingActivity(id: 123, startTime: .now, endTime: nil, userStatus: 0,
                                otherID: ["location": "4", "gesture": "3", "password": "5", "qr": "2"][kind] ?? "0",
                                isLook: false, type: 2, activeType: 2, title: "Test", status: 1,
                                endTimeDescription: "", course: course, ext: "")
    }
}

private final class FaceFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var verifiedRequests: Set<String> = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request.capturedForTesting
        let scenario = request.value(forHTTPHeaderField: "X-Face-Scenario") ?? ""
        let uid = request.value(forHTTPHeaderField: "X-Face-UID") ?? "1"
        let query = request.testParameters
        let body: String
        var status = 200
        switch request.url?.lastPathComponent {
        case "analysis": body = "code='+'abcdef'"
        case "getPPTActiveInfo":
            body = "{\"data\":{\"openCheckFaceFlag\":\(["noFace", "challenge"].contains(scenario) ? 0 : 1),\"ifphoto\":\(scenario == "photo" ? 1 : 0),\"ifrefreshewm\":\(scenario == "qrRotated" ? 1 : 0)}}"
        case "userLogin4Uname.do": body = #"{"msg":{"uid":1,"clientId":"invalid"}}"#
        case "uservalid": body = #"{"_token":"token"}"#
        case "upload": body = #"{"objectId":"attendance-photo"}"#
        case "check-face-result":
            if scenario == "networkFace" { status = 500 }
            let face = query["faceResult"].flatMap { try? JSONReader.object(from: Data($0.utf8)) }
            let valid = query["activeId"] == "123" && face?.string("currentFaceId") == "face-\(uid)"
                && face?.integer("LiveDetectionStatus") == 1 && face?.integer("collectStatus") == 1
                && face?.string("cxtime")?.isEmpty == false
            Self.lock.lock(); Self.verifiedRequests.insert(scenario); Self.lock.unlock()
            body = valid && scenario != "missingFaceEnc" ? "{\"enc\":\"enc-\(uid)\"}" : #"{"msg":"invalid face result"}"#
        case "signDetail":
            Self.lock.lock(); let verified = Self.verifiedRequests.contains(scenario); Self.lock.unlock()
            body = "{\"isOver\":0,\"signCode\":\"\(scenario == "qrRotated" && verified ? "5678" : "1234")\"}"
        case "stuSignajax":
            let validFace = query["currentFaceId"] == "face-\(uid)" && query["faceEnc"] == "enc-\(uid)"
                && query["ifCFP"] == "0" && query["faceCode"] == "" && query["faceEncAid"] == ""
                && query["courseId"] == "1" && query["uid"] == uid && query["deviceCode"] == "device-\(uid)"
            if scenario == "noFace" { body = query["currentFaceId"] == nil ? "success" : "unexpected face" }
            else if scenario == "repeatedChallenge" { body = "checkFace_retry-token" }
            else if scenario == "challenge" && query["enc2"] != "retry-token" { body = "checkFace_retry-token" }
            else if scenario == "badFace" { body = "[face]人脸不匹配" }
            else if scenario == "photo" && query["objectId"] != "attendance-photo" { body = "missing attendance photo" }
            else { body = validFace ? "success" : "invalid face parameters" }
        default: body = "{}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
