import Foundation

enum CaptchaAutomaticResolver {
    enum Resolution: Equatable {
        case solved(String)
        case manual(requiresRefresh: Bool)
    }

    static func resolve(
        imageData: Data,
        predict: (Data) async throws -> Int?,
        verify: (Int) async throws -> String?
    ) async throws -> Resolution {
        try Task.checkCancellation()
        let offset: Int?
        do {
            offset = try await predict(imageData)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return .manual(requiresRefresh: false)
        }
        try Task.checkCancellation()
        guard let offset, (-8...272).contains(offset) else { return .manual(requiresRefresh: false) }
        do {
            let validate = try await verify(offset)
            try Task.checkCancellation()
            guard let validate, !validate.isEmpty else { return .manual(requiresRefresh: true) }
            return .solved(validate)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ChaoxingError where error == .signCancelled || error == .sessionExpired {
            throw error
        } catch {
            try Task.checkCancellation()
            return .manual(requiresRefresh: true)
        }
    }
}
