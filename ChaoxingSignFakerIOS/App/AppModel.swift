import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private let api = ChaoxingAPI()
    private let courseFavoritesStore = CourseFavoritesStore()
    private let sessionStore = ChaoxingSessionStore()

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

    init() {
        guard let persisted = sessionStore.load() else { return }
        api.restore(persisted.session, cookies: persisted.cookies)
        user = persisted.session.user
        favoriteCourseClassIDs = courseFavoritesStore.classIDs(for: persisted.session.user)
    }

    func login(phoneNumber: String, password: String) async {
        guard !isLoggingIn else { return }
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }
        do {
            let session = try await api.login(phoneNumber: phoneNumber, password: password)
            user = session.user
            favoriteCourseClassIDs = courseFavoritesStore.classIDs(for: session.user)
            sessionStore.save(session: session, cookies: api.authenticationCookies)
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

    func prepareOrdinaryOrPhotoSign(_ activity: ChaoxingActivity) async throws -> OrdinaryOrPhotoSignPreparation {
        try await api.prepareOrdinaryOrPhotoSign(activity)
    }

    func signPhoto(_ activity: ChaoxingActivity, jpegData: Data) async throws -> OrdinarySignResult {
        try await api.signPhoto(activity, jpegData: jpegData)
    }

    func prepareLocationSign(_ activity: ChaoxingActivity) async throws -> LocationSignPreparation {
        try await api.prepareLocationSign(activity)
    }

    func signLocation(
        _ activity: ChaoxingActivity,
        location: ChaoxingSignLocation
    ) async throws -> OrdinarySignResult {
        try await api.signLocation(activity, location: location)
    }

    func logout() {
        api.logout()
        sessionStore.clear()
        user = nil
        courses = []
        ongoingActivities = []
        favoriteCourseClassIDs = []
        loginError = nil
        courseError = nil
    }
}

