import Foundation
import Observation

@MainActor @Observable
final class FaceSignCoordinator {
    struct Request: Identifiable {
        let id = UUID()
        let activityID: Int64
        let user: ChaoxingUser
        let isCurrent: Bool
        let api: ChaoxingAPI
    }

    private struct Key: Hashable {
        let activityID: Int64
        let uid: Int
    }

    var request: Request?
    private var pending: Request?
    private var continuation: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    private var activeActivities: Set<Int64> = []
    private var selected: [Key: (String, ChaoxingUser, Bool)] = [:]
    private let store = FacePhotoStore()

    func activate(activityID: Int64) { activeActivities.insert(activityID) }

    func isActive(activityID: Int64) -> Bool { activeActivities.contains(activityID) }

    func select(api: ChaoxingAPI, activity: ChaoxingActivity, currentUID: Int?) async throws -> String {
        try Task.checkCancellation()
        guard isActive(activityID: activity.id) else { throw ChaoxingError.signCancelled }
        guard let user = api.session?.user else { throw ChaoxingError.sessionExpired }
        let key = Key(activityID: activity.id, uid: user.uid)
        if let cached = selected[key] { return cached.0 }
        guard continuation == nil else { throw ChaoxingError.invalidInput("请先完成当前账号的人脸照片选择") }
        let next = Request(activityID: activity.id, user: user, isCurrent: user.uid == currentUID, api: api)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                pending = next
                result = nil
                request = next
            }
        } onCancel: {
            Task { @MainActor in self.cancel(activityID: activity.id) }
        }
    }

    func choose(_ objectID: String, requestID: UUID) {
        guard let pending, pending.id == requestID else { return }
        selected[Key(activityID: pending.activityID, uid: pending.user.uid)] = (objectID, pending.user, pending.isCurrent)
        result = .success(objectID)
        request = nil
    }

    func dismissSelection() {
        guard let continuation else { return }
        let result = result ?? .failure(ChaoxingError.signCancelled)
        self.continuation = nil
        self.result = nil
        pending = nil
        request = nil
        continuation.resume(with: result)
    }

    func cancel(activityID: Int64) {
        guard pending?.activityID == activityID else { return }
        result = .failure(ChaoxingError.signCancelled)
        request = nil
        dismissSelection()
    }

    func finish(activityID: Int64, uid: Int, isFailure: Bool) {
        let key = Key(activityID: activityID, uid: uid)
        guard let selection = selected[key] else { return }
        store.recordUse(objectID: selection.0, for: selection.1, isCurrent: selection.2, isFailure: isFailure)
        if isFailure { selected.removeValue(forKey: key) }
    }

    func resetAll() {
        activeActivities = []
        if let pending { cancel(activityID: pending.activityID) }
        selected = [:]
    }

    func reset(activityID: Int64) {
        activeActivities.remove(activityID)
        cancel(activityID: activityID)
        selected = selected.filter { $0.key.activityID != activityID }
    }
}
