import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let api = ChaoxingAPI()

    var user: ChaoxingUser?
    var courses: [ChaoxingCourse] = []
    var isLoggingIn = false
    var isLoadingCourses = false
    var loginError: String?
    var courseError: String?

    func login(phoneNumber: String, password: String) async {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }
        do {
            user = try await api.login(phoneNumber: phoneNumber, password: password).user
            await loadCourses()
        } catch {
            loginError = error.localizedDescription
        }
    }

    func loadCourses() async {
        guard user != nil, !isLoadingCourses else { return }
        isLoadingCourses = true
        courseError = nil
        defer { isLoadingCourses = false }
        do {
            courses = try await api.courses()
        } catch {
            courseError = error.localizedDescription
        }
    }

    func loadActivities(for course: ChaoxingCourse) async throws -> [ChaoxingActivity] {
        try await api.activities(for: course)
    }

    func prepareOrdinarySign(_ activity: ChaoxingActivity) async throws -> OrdinarySignPreparation {
        try await api.prepareOrdinarySign(activity)
    }

    func signOrdinary(_ activity: ChaoxingActivity) async throws -> OrdinarySignResult {
        try await api.signOrdinary(activity)
    }

    func logout() {
        api.logout()
        user = nil
        courses = []
        loginError = nil
        courseError = nil
    }
}

