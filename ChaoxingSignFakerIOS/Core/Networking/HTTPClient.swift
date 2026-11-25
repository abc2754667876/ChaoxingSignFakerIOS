import Foundation

struct HTTPResponse {
    let data: Data
    let response: HTTPURLResponse

    var text: String {
        String(data: data, encoding: .utf8) ?? ""
    }
}

final class HTTPClient {
    static let defaultUserAgent = "Dalvik/2.1.0 (Linux; U; Android 12; SM-N9006 Build/8aba9e4.0) (schild:2d97f7b9439f21333c946878fc4d6ccb) (device:SM-N9006) Language/zh_CN com.chaoxing.mobile/ChaoXingStudy_3_6.7.5_android_phone_10941_314 (@Kalimdor)_68f184fd763546c1a04ab3a09b3deebb"

    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage

    init(
        cookieStorage: HTTPCookieStorage = .shared,
        configuration: URLSessionConfiguration = .ephemeral
    ) {
        self.cookieStorage = cookieStorage
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = cookieStorage
        configuration.httpShouldSetCookies = true
        var headers = configuration.httpAdditionalHeaders ?? [:]
        headers["User-Agent"] = Self.defaultUserAgent
        configuration.httpAdditionalHeaders = headers
        session = URLSession(configuration: configuration)
    }

    func clearChaoxingCookies() {
        chaoxingCookies.forEach(cookieStorage.deleteCookie)
    }

    var chaoxingCookies: [HTTPCookie] {
        cookieStorage.cookies?.filter {
            $0.domain.hasSuffix("chaoxing.com")
        } ?? []
    }

    func restore(cookies: [HTTPCookie]) {
        clearChaoxingCookies()
        cookies.forEach(cookieStorage.setCookie)
    }

    func send(
        _ url: URL,
        method: String = "GET",
        query: [URLQueryItem] = [],
        form: [(String, String)]? = nil,
        headers: [String: String] = [:]
    ) async throws -> HTTPResponse {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ChaoxingError.invalidInput("请求地址无效")
        }
        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }
        guard let finalURL = components.url else {
            throw ChaoxingError.invalidInput("请求参数无效")
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if let form {
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = formEncoded(form).data(using: .utf8)
        }

        do {
            return try await execute(request)
        } catch let error as ChaoxingError {
            throw error
        } catch {
            throw ChaoxingError.server(error.localizedDescription)
        }
    }

    func sendMultipart(
        _ url: URL,
        fields: [(String, String)],
        fileField: String,
        filename: String,
        mimeType: String,
        fileData: Data
    ) async throws -> HTTPResponse {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        for (name, value) in fields {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.appendUTF8("\(value)\r\n")
        }
        body.appendUTF8("--\(boundary)\r\n")
        body.appendUTF8("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
        body.appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.appendUTF8("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            return try await execute(request)
        } catch let error as ChaoxingError {
            throw error
        } catch {
            throw ChaoxingError.server(error.localizedDescription)
        }
    }

    private func execute(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ChaoxingError.invalidResponse("服务器响应无效")
        }
        guard (200...399).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw ChaoxingError.sessionExpired
            }
            throw ChaoxingError.server("网络请求失败（HTTP \(response.statusCode)）")
        }
        return HTTPResponse(data: data, response: response)
    }

    private func formEncoded(_ values: [(String, String)]) -> String {
        values.map { key, value in
            "\(formEscape(key))=\(formEscape(value))"
        }.joined(separator: "&")
    }

    private func formEscape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? value
    }
}

private extension Data {
    mutating func appendUTF8(_ value: String) {
        append(value.data(using: .utf8) ?? Data())
    }
}
