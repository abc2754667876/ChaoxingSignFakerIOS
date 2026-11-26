import CoreLocation
import Foundation

struct ChaoxingSchool: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let name: String
}

struct ChaoxingUser: Hashable, Codable, Sendable {
    let uid: Int
    let puid: Int
    let defaultFID: Int
    let name: String
    let phoneNumber: String
    let avatarURL: URL?
    let schools: [ChaoxingSchool]
    var clientID: String? = nil
}

struct ChaoxingCourse: Identifiable, Hashable, Sendable {
    var id: Int { classID }

    let courseName: String
    let teacherName: String?
    let courseID: Int64
    let classID: Int
    let className: String
    let imageURL: URL?
    let schoolName: String?
}

enum ChaoxingSignKind: String, Hashable, Sendable {
    case ordinaryOrPhoto = "0"
    case qrCode = "2"
    case gesture = "3"
    case location = "4"
    case password = "5"
    case unknown

    init(otherID: String) {
        self = Self(rawValue: otherID) ?? .unknown
    }

    var title: String {
        switch self {
        case .ordinaryOrPhoto: "普通/拍照签到"
        case .qrCode: "二维码签到"
        case .gesture: "手势签到"
        case .location: "位置签到"
        case .password: "签到码签到"
        case .unknown: "未知签到"
        }
    }

    var systemImage: String {
        switch self {
        case .ordinaryOrPhoto: "hand.tap"
        case .gesture: "hand.draw"
        case .location: "location"
        case .qrCode: "qrcode"
        case .password: "ellipsis.rectangle"
        case .unknown: "questionmark.circle"
        }
    }
}

struct ChaoxingActivity: Identifiable, Hashable, Sendable {
    let id: Int64
    let startTime: Date
    let endTime: Date?
    let userStatus: Int
    let otherID: String
    let isLook: Bool
    let type: Int
    let activeType: Int
    let title: String
    let status: Int
    let endTimeDescription: String
    let course: ChaoxingCourse
    let ext: String

    var kind: ChaoxingSignKind { ChaoxingSignKind(otherID: otherID) }
    var isActive: Bool { status == 1 }
    var isOrdinaryCandidate: Bool { kind == .ordinaryOrPhoto }
    var isSupported: Bool {
        kind == .ordinaryOrPhoto || kind == .gesture || kind == .location || kind == .qrCode || kind == .password
    }
}

struct ChaoxingSignLocation: Equatable, Sendable {
    let address: String
    let bd09Latitude: Double
    let bd09Longitude: Double

    /// Both GPS and favorites enter here as normalized WGS-84. Only this boundary
    /// converts to the BD-09 representation consumed by the H5 sign endpoint.
    init(address: String, wgs84Coordinate: CLLocationCoordinate2D) {
        self.address = address
        let coordinate = CoordinateConverter.wgs84ToBD09(wgs84Coordinate)
        bd09Latitude = (coordinate.latitude * 1_000_000).rounded() / 1_000_000
        bd09Longitude = (coordinate.longitude * 1_000_000).rounded() / 1_000_000
    }
}

struct LocationSignDetail: Equatable, Sendable {
    let bd09Latitude: Double?
    let bd09Longitude: Double?
    let range: Int?
}

enum LocationSignPreparation: Equatable, Sendable {
    case ready(LocationSignDetail)
    case alreadySigned(LocationSignDetail)
    case expired(LocationSignDetail)
}

enum GestureSignPreparation: Equatable, Sendable {
    case ready(isLocationRequired: Bool)
    case alreadySigned(isLocationRequired: Bool)
    case expired(isLocationRequired: Bool)
}

enum CodeSignPreparation: Equatable, Sendable {
    case ready(isLocationRequired: Bool, codeLength: Int?, isRefreshingQR: Bool)
    case alreadySigned(isLocationRequired: Bool, codeLength: Int?, isRefreshingQR: Bool)
    case expired
}

struct ParsedSignQRCode: Equatable, Sendable {
    let activeID: Int64?
    let code: String?
    let enc: String

    init(_ rawValue: String) throws {
        let values: [String: String]
        if rawValue.hasPrefix("SIGNIN:") {
            let content = String(rawValue.dropFirst("SIGNIN:".count)).components(separatedBy: "-")[0]
            values = Self.parameters(content)
        } else if let components = URLComponents(string: rawValue),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" {
            values = Dictionary(components.queryItems?.compactMap { item in
                item.value.map { (item.name, $0) }
            } ?? [], uniquingKeysWith: { first, _ in first })
        } else {
            throw ChaoxingError.invalidInput("二维码格式无效")
        }
        guard let enc = values["enc"], !enc.isEmpty else {
            throw ChaoxingError.invalidInput("二维码缺少签到凭证")
        }
        self.enc = enc
        activeID = (values["id"] ?? values["aid"]).flatMap(Int64.init)
        code = values["c"].flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func parameters(_ text: String) -> [String: String] {
        Dictionary(text.split(separator: "&").compactMap { part in
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return nil }
            return (String(pair[0]), String(pair[1]).removingPercentEncoding ?? String(pair[1]))
        }, uniquingKeysWith: { first, _ in first })
    }
}

enum OrdinarySignPreparation: Equatable, Sendable {
    case ready
    case alreadySigned
    case expired
}

enum OrdinarySignResult: Equatable, Sendable {
    case success
}

enum OrdinaryOrPhotoSignPreparation: Equatable, Sendable {
    case ready(isPhotoRequired: Bool)
    case alreadySigned(isPhotoRequired: Bool)
    case expired(isPhotoRequired: Bool)
}

