import Foundation
import Observation

@MainActor @Observable
final class CaptchaCoordinator {
    struct Request: Identifiable {
        let id = UUID()
        let activity: ChaoxingActivity
        let user: ChaoxingUser
        let api: ChaoxingAPI
    }

    var request: Request?
    private var pending: Request?
    private var continuation: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    private var activeActivities: Set<Int64> = []

    func activate(activityID: Int64) { activeActivities.insert(activityID) }

    func resolve(api: ChaoxingAPI, activity: ChaoxingActivity) async throws -> String {
        try Task.checkCancellation()
        guard activeActivities.contains(activity.id) else { throw ChaoxingError.signCancelled }
        guard let user = api.session?.user else { throw ChaoxingError.sessionExpired }
        guard continuation == nil else { throw ChaoxingError.invalidInput("请先完成当前账号的滑块验证") }
        let next = Request(activity: activity, user: user, api: api)
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                pending = next
                result = nil
                request = next
            }
        } onCancel: {
            Task { @MainActor in self.cancel(requestID: next.id) }
        }
    }

    func complete(_ validate: String, requestID: UUID) {
        guard pending?.id == requestID, request?.id == requestID, !validate.isEmpty else { return }
        result = .success(validate)
        request = nil
    }

    func dismiss(requestID: UUID) {
        guard pending?.id == requestID, let continuation else { return }
        let result = result ?? .failure(ChaoxingError.signCancelled)
        self.continuation = nil
        self.result = nil
        pending = nil
        request = nil
        continuation.resume(with: result)
    }

    private func cancel(requestID: UUID) {
        guard pending?.id == requestID else { return }
        result = .failure(ChaoxingError.signCancelled)
        request = nil
        dismiss(requestID: requestID)
    }

    func reset(activityID: Int64) {
        activeActivities.remove(activityID)
        if let pending, pending.activity.id == activityID { cancel(requestID: pending.id) }
    }

    func resetAll() {
        activeActivities = []
        if let pending { cancel(requestID: pending.id) }
    }
}
