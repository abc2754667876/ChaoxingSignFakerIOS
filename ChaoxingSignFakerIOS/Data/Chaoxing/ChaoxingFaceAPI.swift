import CryptoKit
import Foundation
import Security

enum ChaoxingFaceSignature {
    static func result(objectID: String, clientID: String?, timestamp: String) -> JSONObject {
        var result: JSONObject = [
            "currentFaceId": objectID, "LiveDetectionStatus": 1,
            "collectStatus": 1, "cxtime": timestamp
        ]
        if let clientID, let device = decodeClientID(clientID),
           let cid = device.string("cid"), let secret = device.string("sc") {
            let fields = ["currentFaceId": objectID, "LiveDetectionStatus": "1",
                          "collectStatus": "1", "cxtime": timestamp, "cxcid": cid]
            let raw = fields.keys.sorted().map { $0 + fields[$0]! }.joined() + secret
            result["cxcid"] = cid
            result["signToken"] = Insecure.MD5.hash(data: Data(raw.utf8))
                .map { String(format: "%02x", $0) }.joined()
        }
        return result
    }

    static func decodeClientID(_ value: String, keyData suppliedKey: Data? = nil) -> JSONObject? {
        let publicKey = "MIGJAoGBALv13w63SEJvHFIhILrHxILBMGykVLOUsoclRiqgU27VNJFrDiERiQ6e8RovVXKjFXoddwOvPBi9oVlplo9A8Wd8IdnLl1DDFyaJ+BIepL6gpfDjRizhxUiqdTl33RLsRZJF0GCVfjz2OWpVo1xBKQPHZNiYL4NsCr0VX8FTT0hJAgMBAAE="
        guard let keyData = suppliedKey ?? Data(base64Encoded: publicKey),
              let encrypted = Data(base64Encoded: value, options: .ignoreUnknownCharacters),
              let key = SecKeyCreateWithData(keyData as CFData, [
                kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass: kSecAttrKeyClassPublic
              ] as CFDictionary, nil) else { return nil }
        let blockSize = SecKeyGetBlockSize(key)
        guard !encrypted.isEmpty, encrypted.count.isMultiple(of: blockSize) else { return nil }
        var plaintext = Data()
        for offset in stride(from: 0, to: encrypted.count, by: blockSize) {
            let block = encrypted.subdata(in: offset..<(offset + blockSize))
            guard let recovered = SecKeyCreateEncryptedData(key, .rsaEncryptionRaw, block as CFData, nil) as Data? else { return nil }
            let bytes = [UInt8](recovered)
            guard bytes.count == blockSize, bytes[0] == 0, bytes[1] == 1,
                  let separator = bytes.dropFirst(2).firstIndex(of: 0), separator >= 10,
                  bytes[2..<separator].allSatisfy({ $0 == 255 }) else { return nil }
            plaintext.append(contentsOf: bytes[(separator + 1)...])
        }
        return try? JSONReader.object(from: plaintext)
    }
}

extension ChaoxingAPI {
    func faceParameters(objectID: String, activeID: Int64) async throws -> [URLQueryItem] {
        let clientID = try await loadFaceClientID()
        let result = ChaoxingFaceSignature.result(objectID: objectID, clientID: clientID,
                                                 timestamp: String(Int64(Date().timeIntervalSince1970 * 1_000)))
        let response = try await http.send(
            URL(string: "https://mobilelearn.chaoxing.com/pptSign/check-face-result?DB_STRATEGY=PRIMARY_KEY&STRATEGY_PARA=activeId")!,
            query: [URLQueryItem(name: "activeId", value: String(activeID)),
                    URLQueryItem(name: "faceResult", value: JSONReader.string(from: result))]
        )
        let payload = try JSONReader.object(from: response.data)
        guard let enc = payload.string("enc")?.nilIfEmpty else {
            throw ChaoxingError.faceFailed(payload.string("msg")?.nilIfEmpty ?? "获取人脸校验凭证失败，请更换照片后重试")
        }
        return [URLQueryItem(name: "currentFaceId", value: objectID),
                URLQueryItem(name: "ifCFP", value: "0"),
                URLQueryItem(name: "faceEnc", value: enc),
                URLQueryItem(name: "faceCode", value: ""),
                URLQueryItem(name: "faceEncAid", value: "")]
    }

    func defaultFacePhoto() async throws -> Data {
        let response = try await http.send(URL(string: "https://mobilelearn.chaoxing.com/v2/apis/sign/collectionfilephotoEnc?DB_STRATEGY=DEFAULT")!)
        let payload = try JSONReader.object(from: response.data)
        guard let objectID = payload.object("data")?.string("oldObjectId")?.nilIfEmpty,
              objectID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }),
              let url = URL(string: "https://p.cldisk.com/star4/\(objectID)/origin.jpg") else {
            throw ChaoxingError.invalidResponse("该账号没有可用的默认人脸照片，请拍照或从相册选择")
        }
        return try await http.send(url).data
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
