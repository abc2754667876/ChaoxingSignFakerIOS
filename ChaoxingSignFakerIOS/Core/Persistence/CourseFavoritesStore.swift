import Foundation

struct CourseFavoritesStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func classIDs(for user: ChaoxingUser) -> Set<Int> {
        let values = defaults.array(forKey: key(for: user)) ?? []
        return Set(values.compactMap { ($0 as? NSNumber)?.intValue })
    }

    func save(classIDs: Set<Int>, for user: ChaoxingUser) {
        defaults.set(classIDs.sorted(), forKey: key(for: user))
    }

    private func key(for user: ChaoxingUser) -> String {
        "favoriteCourseClassIDs.\(user.puid).\(user.defaultFID)"
    }
}
