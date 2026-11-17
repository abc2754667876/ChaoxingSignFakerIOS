import Foundation

struct ChaoxingSchool: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
}

struct ChaoxingUser: Hashable, Sendable {
    let uid: Int
    let puid: Int
    let defaultFID: Int
    let name: String
    let phoneNumber: String
    let avatarURL: URL?
    let schools: [ChaoxingSchool]
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
        case .qrCode: "qrcode.viewfinder"
        case .gesture: "circle.grid.3x3"
        case .location: "location"
        case .password: "number.square"
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

