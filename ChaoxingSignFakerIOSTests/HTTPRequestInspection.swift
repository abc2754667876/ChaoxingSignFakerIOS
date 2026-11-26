import Foundation

extension URLRequest {
    var capturedForTesting: URLRequest {
        guard httpBody == nil, let stream = httpBodyStream else { return self }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        var copy = self
        copy.httpBody = data
        return copy
    }

    var testParameters: [String: String] {
        let request = capturedForTesting
        var items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        if let body = request.httpBody,
           let text = String(data: body, encoding: .utf8),
           request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/x-www-form-urlencoded") == true {
            var form = URLComponents()
            form.percentEncodedQuery = text.replacingOccurrences(of: "+", with: "%20")
            items += form.queryItems ?? []
        }
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }
}
