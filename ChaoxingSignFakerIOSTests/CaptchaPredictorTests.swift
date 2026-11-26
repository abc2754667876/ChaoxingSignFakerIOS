import Foundation
import Testing
import UIKit
@testable import ChaoxingSignFakerIOS

@MainActor
struct CaptchaPredictorTests {
    @Test func padsAtBottomAndBuildsRGBChannelsWithoutFlipping() throws {
        let tensor = try CaptchaTensor(imageData: imageData())
        let plane = 640 * 640
        #expect(tensor.paddedLength == 320)
        #expect(tensor.values.count == 3 * plane)
        #expect(tensor.values[20 * 640 + 20] > 0.99)
        #expect(tensor.values[2 * plane + 200 * 640 + 20] > 0.99)
        #expect(tensor.values[500 * 640 + 20] == 0)
        #expect(tensor.values[plane + 500 * 640 + 20] == 0)
        #expect(tensor.values[2 * plane + 500 * 640 + 20] == 0)
    }

    @Test func loadsBundledORTAndRunsRealCPUInference() async throws {
        let resource = try #require(Bundle.main.url(forResource: "captcha", withExtension: "ort"))
        #expect(try Data(contentsOf: resource).count > 5_000_000)
        let predictor = CaptchaPredictor()
        let offset = try await predictor.predict(imageData: imageData())
        #expect(offset == nil || (-8...272).contains(offset!))
    }

    @Test func restoresStrongestDetectionToOriginalCoordinates() {
        let output: [Float] = [300, 400, 100, 100, 40, 40, 40, 40, 0.9, 0.5]
        let offset = output.withUnsafeBufferPointer { CaptchaDetection.offset(values: $0, columns: 2, paddedLength: 320) }
        #expect(offset == 136)
        let noDetection: [Float] = [300, 100, 40, 40, 0.1]
        #expect(noDetection.withUnsafeBufferPointer { CaptchaDetection.offset(values: $0, columns: 1, paddedLength: 320) } == nil)
        let invalid: [Float] = [.nan, 100, 40, 40, 0.9]
        #expect(invalid.withUnsafeBufferPointer { CaptchaDetection.offset(values: $0, columns: 1, paddedLength: 320) } == nil)
    }

    @Test(arguments: ["success", "noDetection", "loadFailure", "rejected", "expired", "empty"])
    func automaticallyVerifiesAtMostOnceAndFallsBackToManual(_ scenario: String) async throws {
        var predictions = 0
        var verifications = 0
        let result = try await CaptchaAutomaticResolver.resolve(imageData: Data()) { _ in
            predictions += 1
            if scenario == "loadFailure" { throw ChaoxingError.invalidResponse("model") }
            return scenario == "noDetection" ? nil : 136
        } verify: { offset in
            verifications += 1
            #expect(offset == 136)
            if scenario == "expired" { throw ChaoxingError.captchaFailed("expired") }
            if scenario == "rejected" { return nil }
            return scenario == "empty" ? "" : "validated"
        }
        #expect(predictions == 1)
        #expect(verifications == (["noDetection", "loadFailure"].contains(scenario) ? 0 : 1))
        #expect(result == (scenario == "success" ? .solved("validated") : .manual(requiresRefresh: ["rejected", "expired", "empty"].contains(scenario))))
    }

    @Test func cancelsAfterPredictionBeforeNetworkVerification() async throws {
        var verified = false
        let task = Task {
            try await CaptchaAutomaticResolver.resolve(imageData: Data()) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return 136
            } verify: { _ in verified = true; return "stale" }
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!verified)
    }

    @Test(arguments: [ChaoxingError.signCancelled, ChaoxingError.sessionExpired])
    func preservesCancellationAndAccountErrors(_ expected: ChaoxingError) async throws {
        await #expect(throws: expected) {
            try await CaptchaAutomaticResolver.resolve(imageData: Data()) { _ in 136 } verify: { _ in throw expected }
        }
    }

    private func imageData() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 160), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 80))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 80, width: 320, height: 80))
        }
        return try #require(image.pngData())
    }
}
