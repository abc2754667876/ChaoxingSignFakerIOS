import CaptchaRuntime
import CoreGraphics
import Foundation
import ImageIO

actor CaptchaPredictor {
    static let shared = CaptchaPredictor()
    private var session: OpaquePointer?
    private var isUnavailable = false

    deinit { if let session { CSFCaptchaDestroy(session) } }

    func predict(imageData: Data) throws -> Int? {
        try Task.checkCancellation()
        guard !isUnavailable else { return nil }
        if session == nil {
            guard let path = Bundle.main.path(forResource: "captcha", ofType: "ort") else {
                isUnavailable = true
                return nil
            }
            var error: UnsafeMutablePointer<CChar>?
            session = CSFCaptchaCreate(path, &error)
            defer { if let error { CSFCaptchaFree(error) } }
            guard session != nil else {
                isUnavailable = true
                throw ChaoxingError.invalidResponse(error.map { String(cString: $0) } ?? "验证码模型加载失败")
            }
        }
        let input = try CaptchaTensor(imageData: imageData)
        var columns = 0
        var error: UnsafeMutablePointer<CChar>?
        let output = input.values.withUnsafeBufferPointer {
            CSFCaptchaRun(session, $0.baseAddress, $0.count, &columns, &error)
        }
        defer {
            if let output { CSFCaptchaFree(output) }
            if let error { CSFCaptchaFree(error) }
        }
        try Task.checkCancellation()
        guard let output else {
            isUnavailable = true
            throw ChaoxingError.invalidResponse(error.map { String(cString: $0) } ?? "验证码模型识别失败")
        }
        return CaptchaDetection.offset(values: UnsafeBufferPointer(start: output, count: columns * 5),
                                       columns: columns, paddedLength: input.paddedLength)
    }
}

struct CaptchaTensor: Sendable {
    let values: [Float]
    let paddedLength: Int

    nonisolated init(imageData: Data) throws {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0, max(image.width, image.height) <= 8192 else {
            throw ChaoxingError.invalidResponse("无法处理验证码图片")
        }
        let length = max(image.width, image.height)
        let pixelCount = 640 * 640
        var pixels = [UInt8](repeating: 0, count: pixelCount * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 640, height: 640,
                                          bitsPerComponent: 8, bytesPerRow: 640 * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 640, height: 640))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 640 - Double(image.height) * 640 / Double(length),
                                           width: Double(image.width) * 640 / Double(length),
                                           height: Double(image.height) * 640 / Double(length)))
            return true
        }
        guard rendered else { throw ChaoxingError.invalidResponse("无法处理验证码图片") }
        var values = [Float](repeating: 0, count: pixelCount * 3)
        for index in 0..<pixelCount {
            values[index] = Float(pixels[index * 4]) / 255
            values[pixelCount + index] = Float(pixels[index * 4 + 1]) / 255
            values[pixelCount * 2 + index] = Float(pixels[index * 4 + 2]) / 255
        }
        self.values = values
        paddedLength = length
    }
}

enum CaptchaDetection {
    nonisolated static func offset(values: UnsafeBufferPointer<Float>, columns: Int, paddedLength: Int) -> Int? {
        guard columns > 0, values.count == columns * 5, paddedLength > 0 else { return nil }
        var bestScore: Float = 0.25
        var bestX: Float?
        for index in 0..<columns {
            let score = values[4 * columns + index]
            let center = values[index]
            let width = values[2 * columns + index]
            guard score.isFinite, center.isFinite, width.isFinite, width > 0, score >= bestScore else { continue }
            let x = (center - width / 2) * Float(paddedLength) / 640 - 4
            guard x.isFinite, x >= -8, x <= 272 else { continue }
            bestScore = score
            bestX = x
        }
        guard let bestX else { return nil }
        return Int(bestX + 0.5)
    }
}
