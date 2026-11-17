import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let api = ChaoxingAPI()
    private let courseFavoritesStore = CourseFavoritesStore()

    var user: ChaoxingUser?
    var courses: [ChaoxingCourse] = []
    var ongoingActivities: [ChaoxingActivity] = []
    var favoriteCourseClassIDs: Set<Int> = []
    var isLoggingIn = false
    var isLoadingCourses = false
    var isLoadingOngoingActivities = false
    var loginError: String?
    var courseError: String?

    var favoriteCourses: [ChaoxingCourse] {
        courses.filter { favoriteCourseClassIDs.contains($0.classID) }
    }

    func login(phoneNumber: String, password: String) async {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }
        do {
            let loggedInUser = try await api.login(phoneNumber: phoneNumber, password: password).user
            user = loggedInUser
            favoriteCourseClassIDs = courseFavoritesStore.classIDs(for: loggedInUser)
            await loadCourses()
        } catch {
            loginError = error.localizedDescription
        }
    }

    func loadOngoingActivities() async {
        guard user != nil, !isLoadingOngoingActivities else { return }
        isLoadingOngoingActivities = true
        defer { isLoadingOngoingActivities = false }

        let availableSince = Date().addingTimeInterval(-20 * 60)
        var loadedActivities: [ChaoxingActivity] = []
        for course in courses {
            guard let activities = try? await api.activities(for: course) else { continue }
            loadedActivities.append(contentsOf: activities.filter {
                $0.isActive && $0.startTime > availableSince
            })
        }
        ongoingActivities = loadedActivities
            .reduce(into: [Int64: ChaoxingActivity]()) { result, activity in
                result[activity.id] = activity
            }
            .values
            .sorted { $0.startTime > $1.startTime }
    }

    func refreshHome() async {
        await loadCourses()
        await loadOngoingActivities()
    }

    func toggleFavorite(_ course: ChaoxingCourse) {
        guard let user else { return }
        var updatedClassIDs = favoriteCourseClassIDs
        if updatedClassIDs.contains(course.classID) {
            updatedClassIDs.remove(course.classID)
        } else {
            updatedClassIDs.insert(course.classID)
        }
        favoriteCourseClassIDs = updatedClassIDs
        courseFavoritesStore.save(classIDs: updatedClassIDs, for: user)
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
        ongoingActivities = []
        favoriteCourseClassIDs = []
        loginError = nil
        courseError = nil
    }
}

