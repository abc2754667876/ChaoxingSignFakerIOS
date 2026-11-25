import Foundation
import Testing
@testable import ChaoxingSignFakerIOS

@MainActor
struct QRCodeValidationTests {
    @Test(arguments: [
        "fixedMissingCode", "fixedDifferentCode", "fixedMissingStatus", "fixedUnknownStatus",
        "dynamicMatchingCode", "dynamicMissingStatus", "dynamicMissingCode", "encOnly"
    ])
    func acceptsValidCodesThroughScanAndSubmission(_ scenario: String) async throws {
        let api = makeAPI(scenario)
        let code = try parsedCode(scenario)
        #expect(try await api.checkQRCode(code, for: activity))
        #expect(try await api.signCode(activity, code: nil, qrCode: code, location: nil) == .success)
    }

    @Test(arguments: ["dynamicDifferentCode", "dynamicMissingStatusDifferentCode"])
    func rejectsRotatedDynamicCodeAtBothEntrances(_ scenario: String) async throws {
        let api = makeAPI(scenario)
        let code = try parsedCode()
        #expect(try await !api.checkQRCode(code, for: activity))
        await #expect(throws: ChaoxingError.invalidInput("二维码已过期，请重新扫描")) {
            try await api.signCode(activity, code: nil, qrCode: code, location: nil)
        }
    }

    @Test(arguments: ["fixedEnded", "dynamicEnded"])
    func reportsEndedActivitySeparately(_ scenario: String) async throws {
        let api = makeAPI(scenario)
        let code = try parsedCode()
        await #expect(throws: ChaoxingError.signExpired) {
            try await api.checkQRCode(code, for: activity)
        }
        await #expect(throws: ChaoxingError.signExpired) {
            try await api.signCode(activity, code: nil, qrCode: code, location: nil)
        }
    }

    @Test(arguments: ["missingRefreshMode", "detailNetworkFailure", "invalidDetailJSON"])
    func doesNotMislabelInvalidResponsesAsExpired(_ scenario: String) async throws {
        let api = makeAPI(scenario)
        let code = try parsedCode()
        do {
            _ = try await api.checkQRCode(code, for: activity)
            Issue.record("Invalid response was accepted")
        } catch let error as ChaoxingError {
            switch error {
            case .invalidResponse, .server: break
            default: Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test func rejectsCodeFromAnotherActivity() async throws {
        let api = makeAPI("fixedMissingCode")
        let code = try ParsedSignQRCode("SIGNIN:id=999&c=456&enc=token")
        await #expect(throws: ChaoxingError.invalidInput("二维码与当前活动不匹配")) {
            try await api.checkQRCode(code, for: activity)
        }
    }

    @Test func keepsRefreshSettingsSeparateForEachSession() async throws {
        let fixed = makeAPI("fixedDifferentCode")
        let dynamic = makeAPI("dynamicDifferentCode")
        let code = try parsedCode()
        #expect(try await fixed.checkQRCode(code, for: activity))
        #expect(try await !dynamic.checkQRCode(code, for: activity))
        #expect(try await fixed.signCode(activity, code: nil, qrCode: code, location: nil) == .success)
    }

    @Test func preservesServerExpiryCheckForCodesWithoutC() async throws {
        let api = makeAPI("encOnlyEnded")
        let code = try parsedCode("encOnly")
        await #expect(throws: ChaoxingError.signExpired) {
            try await api.signCode(activity, code: nil, qrCode: code, location: nil)
        }
    }

    @Test(arguments: ["fixedMissingStatusServerEnded", "dynamicMissingStatusServerEnded"])
    func usesSubmissionResultWhenDetailOmitsStatus(_ scenario: String) async throws {
        let api = makeAPI(scenario)
        let code = try parsedCode()
        #expect(try await api.checkQRCode(code, for: activity))
        await #expect(throws: ChaoxingError.signExpired) {
            try await api.signCode(activity, code: nil, qrCode: code, location: nil)
        }
    }

    private func parsedCode(_ scenario: String = "") throws -> ParsedSignQRCode {
        let query = scenario == "encOnly" ? "aid=123&enc=token" : "aid=123&c=456&enc=token"
        return try ParsedSignQRCode("https://mobilelearn.chaoxing.com/newsign?\(query)")
    }

    private func makeAPI(_ scenario: String) -> ChaoxingAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QRCodeFixtureProtocol.self]
        configuration.httpAdditionalHeaders = ["X-QR-Scenario": scenario]
        let api = ChaoxingAPI(http: HTTPClient(configuration: configuration))
        let user = ChaoxingUser(uid: 1, puid: 1, defaultFID: 0, name: "Test", phoneNumber: "", avatarURL: nil, schools: [])
        api.restore(ChaoxingSession(user: user, configuredFID: 0, deviceCode: "test"), cookies: [])
        return api
    }

    private var activity: ChaoxingActivity {
        let course = ChaoxingCourse(courseName: "Test", teacherName: nil, courseID: 1, classID: 2,
                                    className: "Test", imageURL: nil, schoolName: nil)
        return ChaoxingActivity(id: 123, startTime: .now, endTime: nil, userStatus: 0, otherID: "2",
                                isLook: false, type: 2, activeType: 2, title: "Test", status: 1,
                                endTimeDescription: "", course: course, ext: "")
    }
}

private final class QRCodeFixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let scenario = request.value(forHTTPHeaderField: "X-QR-Scenario") ?? ""
        let body: String
        var status = 200
        switch request.url?.lastPathComponent {
        case "getPPTActiveInfo":
            body = scenario == "missingRefreshMode" ? #"{"data":{}}"#
                : "{\"data\":{\"ifrefreshewm\":\(scenario.hasPrefix("dynamic") ? 1 : 0)}}"
        case "signDetail":
            if scenario == "invalidDetailJSON" {
                body = "[]"
            } else {
                if scenario == "detailNetworkFailure" { status = 500 }
                var detail: [String: Any] = [:]
                if !scenario.contains("MissingStatus") {
                    detail["isOver"] = scenario.hasSuffix("Ended") ? 1 : 0
                }
                if scenario.hasSuffix("UnknownStatus") { detail["isOver"] = -1 }
                if !scenario.hasSuffix("MissingCode") && !scenario.hasSuffix("ServerEnded") {
                    detail["signCode"] = scenario.hasSuffix("DifferentCode") ? "789" : "456"
                }
                body = JSONReader.string(from: detail)
            }
        case "stuSignajax":
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let enc = query.first { $0.name == "enc" }?.value
            if enc != "token" {
                body = "missing enc"
            } else {
                body = scenario == "encOnlyEnded" || scenario.hasSuffix("ServerEnded") ? "success2" : "success"
            }
        default:
            body = "{}"
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
