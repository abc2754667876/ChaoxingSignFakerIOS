import Foundation

enum ChaoxingSignRoute {
    static let originHost = "mobilelearn.chaoxing.com"
    static let routedHost = "data-xxt.aichaoxing.com"

    static func route(_ request: URLRequest) -> HTTPRequestRoute? {
        guard let url = request.url,
              [originHost, routedHost].contains(url.host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var primary = request
        components.host = routedHost
        primary.url = components.url
        primary.setValue(originHost, forHTTPHeaderField: "Host")
        var fallback = request
        components.host = originHost
        fallback.url = components.url
        fallback.setValue(nil, forHTTPHeaderField: "Host")
        return HTTPRequestRoute(primary: primary, fallback: fallback)
    }
}
