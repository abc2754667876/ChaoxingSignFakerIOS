import Foundation

enum ChaoxingCrypto {
    private static let transferKey = "u2oh6Vu^HWe4_AES"

    static func encryptLoginValue(_ value: String) throws -> String {
        let key = Array(transferKey.utf8)
        let input = Array(value.utf8)
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0

        let status = key.withUnsafeBytes { keyBytes in
            key.withUnsafeBytes { ivBytes in
                input.withUnsafeBytes { inputBytes in
                    output.withUnsafeMutableBytes { outputBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            kCCKeySizeAES128,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            input.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw ChaoxingError.invalidResponse("登录参数加密失败（\(status)）")
        }
        return Data(output.prefix(outputLength)).base64EncodedString()
    }
}

