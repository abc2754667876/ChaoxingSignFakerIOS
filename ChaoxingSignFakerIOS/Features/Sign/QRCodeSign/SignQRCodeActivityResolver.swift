import Foundation

@MainActor
enum SignQRCodeActivityResolver {
    static func resolve(
        _ code: ParsedSignQRCode,
        cachedActivities: [ChaoxingActivity],
        loadCourses: () async throws -> [ChaoxingCourse],
        loadActivities: (ChaoxingCourse) async throws -> [ChaoxingActivity]
    ) async throws -> ChaoxingActivity {
        guard let activeID = code.activeID, activeID > 0 else {
            throw ChaoxingError.invalidInput("二维码缺少有效的活动编号，请从课程活动中进入二维码签到")
        }
        if let activity = cachedActivities.first(where: { $0.id == activeID }) {
            return try validate(activity)
        }
        // The home feed only contains recent activities. Search all courses so
        // older, already signed, and newly created activities can also be found.
        let courses = try await loadCourses()
        try Task.checkCancellation()
        var firstError: Error?
        for course in courses {
            try Task.checkCancellation()
            let activities: [ChaoxingActivity]
            do {
                activities = try await loadActivities(course)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                firstError = firstError ?? error
                continue
            }
            try Task.checkCancellation()
            if let activity = activities.first(where: { $0.id == activeID }) {
                return try validate(activity)
            }
        }
        // A failed request means the activity might belong to an unread course.
        if let firstError { throw firstError }
        throw ChaoxingError.invalidInput("未在当前账号的课程中找到该签到活动，请确认二维码与登录账号是否正确")
    }

    private static func validate(_ activity: ChaoxingActivity) throws -> ChaoxingActivity {
        guard activity.kind == .qrCode else {
            throw ChaoxingError.invalidInput("该二维码对应的活动不是二维码签到")
        }
        return activity
    }
}
