import Foundation

typealias JSONObject = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func object(_ key: String) -> JSONObject? {
        self[key] as? JSONObject
    }

    func array(_ key: String) -> [Any]? {
        self[key] as? [Any]
    }

    func string(_ key: String) -> String? {
        switch self[key] {
        case let value as String:
            value
        case let value as NSNumber:
            value.stringValue
        default:
            nil
        }
    }

    func integer(_ key: String) -> Int? {
        switch self[key] {
        case let value as Int:
            value
        case let value as NSNumber:
            value.intValue
        case let value as String:
            Int(value)
        default:
            nil
        }
    }

    func int64(_ key: String) -> Int64? {
        switch self[key] {
        case let value as Int64:
            value
        case let value as NSNumber:
            value.int64Value
        case let value as String:
            Int64(value)
        default:
            nil
        }
    }

    func double(_ key: String) -> Double? {
        switch self[key] {
        case let value as Double:
            value
        case let value as NSNumber:
            value.doubleValue
        case let value as String:
            Double(value)
        default:
            nil
        }
    }

    func boolean(_ key: String) -> Bool? {
        switch self[key] {
        case let value as Bool:
            value
        case let value as NSNumber:
            value.boolValue
        case let value as String:
            ["1", "true", "yes"].contains(value.lowercased())
        default:
            nil
        }
    }
}

enum JSONReader {
    static func object(from data: Data) throws -> JSONObject {
        guard let object = try JSONSerialization.jsonObject(with: data) as? JSONObject else {
            throw ChaoxingError.invalidResponse("服务器返回了无法识别的数据")
        }
        return object
    }

    static func string(from object: Any?) -> String {
        guard let object, JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let value = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return value
    }
}

