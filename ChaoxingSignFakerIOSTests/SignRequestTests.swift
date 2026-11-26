import Foundation
import Testing
@testable import ChaoxingSignFakerIOS

@MainActor
struct SignRequestTests {
    @Test(arguments: ["success", "notFound", "networkFailure", "cancelled", "serverFailure", "businessFailure"])
    func routesWithAccountCookiesAndFallsBackOnlyWhenNecessary(_ scenario: String) async throws {
        let id = UUID().uuidString
        let configuration = configuration(scenario, id: id)
        let cookies = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "route-\(id)")
        let api = ChaoxingAPI(http: HTTPClient(cookieStorage: cookies, configuration: configuration))
        let cookie = try #require(HTTPCookie(properties: [
            .name: "session", .value: "account-session", .domain: ".chaoxing.com", .path: "/", .secure: "TRUE"
        ]))
        api.http.restore(cookies: [cookie])
        var result: HTTPResponse?
        var failure: Error?
        do {
            result = try await api.http.send(
                URL(string: "https://mobilelearn.chaoxing.com/pptSign/stuSignajax")!,
                method: "POST",
                form: [("name", "中文 + & ="), ("validate", "a+b/c=="), ("enc2", "enc_value"), ("clientip", "")],
                headers: ["Referer": "https://mobilelearn.chaoxing.com/newsign/preSign?activePrimaryId=123",
                          "X-Requested-With": "XMLHttpRequest"]
            )
        } catch { failure = error }
        let requests = SignRequestProtocol.takeRequests(id: id)
        let shouldFallback = ["notFound", "networkFailure"].contains(scenario)
        #expect(requests.count == (shouldFallback ? 2 : 1))
        for (index, request) in requests.enumerated() {
            #expect(request.httpMethod == "POST")
            #expect(request.url?.query == nil)
            #expect(request.testParameters["name"] == "中文 + & =")
            #expect(request.testParameters["validate"] == "a+b/c==")
            #expect(request.testParameters["enc2"] == "enc_value")
            #expect(request.testParameters["clientip"] == "")
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("session=account-session") == true)
            #expect(request.value(forHTTPHeaderField: "X-Requested-With") == "XMLHttpRequest")
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://mobilelearn.chaoxing.com/newsign/preSign?activePrimaryId=123")
            #expect(request.url?.host == (index == 0 ? "data-xxt.aichaoxing.com" : "mobilelearn.chaoxing.com"))
            #expect(request.value(forHTTPHeaderField: "Host") == (index == 0 ? "mobilelearn.chaoxing.com" : nil))
        }
        if scenario == "cancelled" {
            #expect(failure is CancellationError)
        } else if scenario == "serverFailure" {
            #expect((failure as? ChaoxingError) == .server("网络请求失败（HTTP 500）"))
        } else {
            #expect(failure == nil)
            #expect(result?.text == (scenario == "businessFailure" ? "签到环境异常" : "success"))
            #expect(result?.response.url?.host == (shouldFallback ? "mobilelearn.chaoxing.com" : "data-xxt.aichaoxing.com"))
        }
        if scenario == "success" {
            #expect(api.http.chaoxingCookies.contains { $0.name == "routeCookie" && $0.value == "updated" })
        }
    }

    @Test(arguments: ["https://captcha.chaoxing.com/captcha/get/conf", "https://passport2.chaoxing.com/fanyalogin"])
    func leavesOtherServiceHostsUnchanged(_ address: String) async throws {
        let id = UUID().uuidString
        let api = ChaoxingAPI(http: HTTPClient(configuration: configuration("unrelated", id: id)))
        let response = try await api.http.send(try #require(URL(string: address)))
        #expect(response.response.url?.absoluteString == address)
        #expect(response.text == "success")
        let requests = SignRequestProtocol.takeRequests(id: id)
        #expect(requests.count == 1)
        #expect(requests.first?.value(forHTTPHeaderField: "Host") == nil)
    }

    private func configuration(_ scenario: String, id: String) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SignRequestProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Route-Scenario": scenario, "X-Route-Test": id]
        return configuration
    }
}

private final class SignRequestProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var requests: [String: [URLRequest]] = [:]

    static func takeRequests(id: String) -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests.removeValue(forKey: id) ?? []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request.capturedForTesting
        let scenario = request.value(forHTTPHeaderField: "X-Route-Scenario") ?? ""
        let id = request.value(forHTTPHeaderField: "X-Route-Test") ?? ""
        Self.lock.lock()
        Self.requests[id, default: []].append(request)
        Self.lock.unlock()
        let isPrimary = request.url?.host == "data-xxt.aichaoxing.com"
        if isPrimary, ["networkFailure", "cancelled"].contains(scenario) {
            client?.urlProtocol(self, didFailWithError: URLError(scenario == "cancelled" ? .cancelled : .cannotConnectToHost))
            return
        }
        let status = isPrimary && scenario == "notFound" ? 404 : isPrimary && scenario == "serverFailure" ? 500 : 200
        let headers = ["Set-Cookie": "routeCookie=updated; Domain=.chaoxing.com; Path=/; Secure"]
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((scenario == "businessFailure" ? "签到环境异常" : "success").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
