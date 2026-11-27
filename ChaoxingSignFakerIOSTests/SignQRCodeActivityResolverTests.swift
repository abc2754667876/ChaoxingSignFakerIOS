import Foundation
import Testing
@testable import ChaoxingSignFakerIOS

@MainActor
struct SignQRCodeActivityResolverTests {
    @Test func usesCachedActivityWithoutFetchingCourses() async throws {
        let activity = makeActivity()
        let result = try await SignQRCodeActivityResolver.resolve(
            code(), cachedActivities: [activity],
            loadCourses: { Issue.record("Unexpected course request"); return [] },
            loadActivities: { _ in Issue.record("Unexpected activity request"); return [] }
        )
        #expect(result == activity)
    }

    @Test func findsActivityOutsideRecentHomeFeed() async throws {
        let target = makeActivity(status: 2)
        var visited: [Int] = []
        let result = try await SignQRCodeActivityResolver.resolve(
            code(), cachedActivities: [], loadCourses: { [course(1), course(2)] },
            loadActivities: { course in
                visited.append(course.classID)
                return course.classID == 2 ? [target] : []
            }
        )
        #expect(visited == [1, 2])
        #expect(result == target) // Preparation, rather than the home feed, checks expiry.
    }

    @Test func continuesPastAnUnrelatedCourseFailure() async throws {
        let target = makeActivity()
        let result = try await SignQRCodeActivityResolver.resolve(
            code(), cachedActivities: [], loadCourses: { [course(1), course(2)] },
            loadActivities: { course in
                if course.classID == 1 { throw ChaoxingError.server("加载失败") }
                return [target]
            }
        )
        #expect(result == target)
    }

    @Test func preservesNetworkFailureWhenNoMatchCanBeConfirmed() async throws {
        await #expect(throws: ChaoxingError.server("加载失败")) {
            try await SignQRCodeActivityResolver.resolve(
                code(), cachedActivities: [], loadCourses: { [course(1)] },
                loadActivities: { _ in throw ChaoxingError.server("加载失败") }
            )
        }
    }

    @Test(arguments: ["enc=token", "aid=0&enc=token", "aid=-1&enc=token", "aid=abc&enc=token"])
    func rejectsMissingOrInvalidActivityID(_ query: String) async throws {
        let parsed = try ParsedSignQRCode("https://mobilelearn.chaoxing.com/newsign?\(query)")
        await #expect(throws: ChaoxingError.invalidInput("二维码缺少有效的活动编号，请从课程活动中进入二维码签到")) {
            try await SignQRCodeActivityResolver.resolve(
                parsed, cachedActivities: [],
                loadCourses: { Issue.record("Invalid code triggered network request"); return [] },
                loadActivities: { _ in [] }
            )
        }
    }

    @Test func rejectsActivityOfAnotherSignKind() async throws {
        await #expect(throws: ChaoxingError.invalidInput("该二维码对应的活动不是二维码签到")) {
            try await SignQRCodeActivityResolver.resolve(
                code(), cachedActivities: [makeActivity(otherID: "5")],
                loadCourses: { [] }, loadActivities: { _ in [] }
            )
        }
    }

    @Test func reportsUnmatchedActivity() async throws {
        await #expect(throws: ChaoxingError.invalidInput("未在当前账号的课程中找到该签到活动，请确认二维码与登录账号是否正确")) {
            try await SignQRCodeActivityResolver.resolve(
                code(), cachedActivities: [], loadCourses: { [course(1)] },
                loadActivities: { _ in [] }
            )
        }
    }

    @Test func stopsSearchingWhenCancelled() async throws {
        await #expect(throws: CancellationError.self) {
            try await SignQRCodeActivityResolver.resolve(
                code(), cachedActivities: [], loadCourses: { [course(1), course(2)] },
                loadActivities: { _ in throw CancellationError() }
            )
        }
    }

    private func code() throws -> ParsedSignQRCode {
        try ParsedSignQRCode("SIGNIN:id=123&c=456&enc=token")
    }

    private func course(_ id: Int) -> ChaoxingCourse {
        ChaoxingCourse(courseName: "Test", teacherName: nil, courseID: Int64(id), classID: id,
                       className: "Test", imageURL: nil, schoolName: nil)
    }

    private func makeActivity(status: Int = 1, otherID: String = "2") -> ChaoxingActivity {
        ChaoxingActivity(id: 123, startTime: .distantPast, endTime: nil, userStatus: 0,
                         otherID: otherID, isLook: false, type: 2, activeType: 2, title: "Test",
                         status: status, endTimeDescription: "", course: course(2), ext: "")
    }
}
