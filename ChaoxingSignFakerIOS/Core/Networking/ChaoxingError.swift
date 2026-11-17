import Foundation

enum ChaoxingError: LocalizedError, Equatable {
    case invalidInput(String)
    case invalidResponse(String)
    case server(String)
    case sessionExpired
    case unsupportedSign(String)
    case alreadySigned
    case signExpired
    case notInClass
    case captchaRequired
    case outsideLocationRange(Double?)
    case signFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message),
             .invalidResponse(let message),
             .server(let message),
             .unsupportedSign(let message),
             .signFailed(let message):
            message
        case .sessionExpired:
            "登录状态已失效，请重新登录"
        case .alreadySigned:
            "你已经签到过了"
        case .signExpired:
            "签到已截止"
        case .notInClass:
            "当前账号不在该班级"
        case .captchaRequired:
            "本次签到需要滑块验证码，当前版本暂未接入"
        case .outsideLocationRange(let distance):
            if let distance {
                "位置不在设置范围内，距离签到点\(distance.formatted(.number.precision(.fractionLength(0...1))))米"
            } else {
                "位置不在设置范围内"
            }
        }
    }
}

