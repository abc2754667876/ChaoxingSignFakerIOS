import Observation
import SwiftUI

enum AccountSignResult {
    case success, alreadySigned, expired
}

@MainActor @Observable
final class MultiAccountSign {
    enum Status {
        case signing, success, alreadySigned, expired, failure(String)

        var title: String {
            switch self {
            case .signing: "签到中"
            case .success: "签到成功"
            case .alreadySigned: "已签到"
            case .expired: "已截止"
            case .failure: "签到失败"
            }
        }
        var icon: String {
            switch self {
            case .signing: "hourglass"
            case .success, .alreadySigned: "checkmark.circle.fill"
            case .expired: "clock.badge.xmark"
            case .failure: "exclamationmark.triangle.fill"
            }
        }
        var color: Color {
            switch self {
            case .signing: .blue
            case .success, .alreadySigned: .green
            case .expired, .failure: .orange
            }
        }
        var failureMessage: String? {
            if case .failure(let message) = self { return message }
            return nil
        }
    }

    var accounts: [OtherUserAccount] = []
    var selectedIDs: Set<Int> = []
    var completedIDs: Set<Int> = []
    var statuses: [Int: Status] = [:]
    var isShowing = false
    var isSigning = false
    private let store = OtherUserStore()
    private var hasInitializedSelection = false

    func load(current: ChaoxingUser?) {
        accounts = store.load()
        if !hasInitializedSelection {
            if let current { selectedIDs.insert(current.uid) }
            hasInitializedSelection = true
        }
    }

    func otherAccounts(current: ChaoxingUser?) -> [OtherUserAccount] {
        var seen = Set<Int>()
        if let current { seen.insert(current.uid) }
        return accounts.filter { seen.insert($0.session.user.uid).inserted }
    }

    func pendingIDs(current: ChaoxingUser?) -> Set<Int> {
        let available = Set(otherAccounts(current: current).map { $0.session.user.uid })
            .union(current.map { [$0.uid] } ?? [])
        return selectedIDs.intersection(available).subtracting(completedIDs)
    }

    func markCurrent(_ user: ChaoxingUser?, as status: Status) {
        guard let user else { return }
        statuses[user.uid] = status
        completedIDs.insert(user.uid)
    }

    func isCurrentAlreadySigned(_ user: ChaoxingUser?) -> Bool {
        guard let user, let status = statuses[user.uid] else { return false }
        if case .alreadySigned = status { return true }
        return false
    }

    func sign(
        model: AppModel,
        main: () async throws -> AccountSignResult,
        other: (ChaoxingAPI) async throws -> AccountSignResult
    ) async -> Bool {
        guard !isSigning else { return false }
        load(current: model.user)
        let targets = pendingIDs(current: model.user)
        guard !targets.isEmpty else { return false }
        isSigning = true
        defer { isSigning = false }
        var hasFailures = false
        if let user = model.user, targets.contains(user.uid) {
            statuses[user.uid] = .signing
            do { record(try await main(), for: user.uid) }
            catch {
                if record(error, for: user.uid) { hasFailures = true }
                if error is CancellationError || (error as? ChaoxingError) == .signCancelled { return true }
            }
        }
        for account in otherAccounts(current: model.user) where targets.contains(account.session.user.uid) {
            let uid = account.session.user.uid
            statuses[uid] = .signing
            do {
                let result = try await model.signForOther(account) { api in try await other(api) }
                record(result, for: uid)
            } catch {
                if record(error, for: uid) { hasFailures = true }
                if error is CancellationError || (error as? ChaoxingError) == .signCancelled { return true }
            }
        }
        return hasFailures
    }

    private func record(_ result: AccountSignResult, for uid: Int) {
        completedIDs.insert(uid)
        switch result {
        case .success: statuses[uid] = .success
        case .alreadySigned: statuses[uid] = .alreadySigned
        case .expired: statuses[uid] = .expired
        }
    }

    private func record(_ error: Error, for uid: Int) -> Bool {
        if let error = error as? ChaoxingError {
            switch error {
            case .alreadySigned: record(.alreadySigned, for: uid); return false
            case .signExpired: record(.expired, for: uid); return false
            default: break
            }
        }
        statuses[uid] = .failure(error.localizedDescription)
        return true
    }
}

struct MultiAccountChooser: View {
    let model: AppModel
    @Bindable var multi: MultiAccountSign

    var body: some View {
        NavigationStack {
            List {
                Section("用户列表") {
                    if let user = model.user { row(user, isCurrent: true) }
                    ForEach(multi.otherAccounts(current: model.user)) { account in
                        row(account.session.user, isCurrent: false)
                    }
                }
            }
            .navigationTitle("选择需要签到的用户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { multi.isShowing = false } } }
        }
    }

    private func row(_ user: ChaoxingUser, isCurrent: Bool) -> some View {
        Button {
            if multi.selectedIDs.contains(user.uid) { multi.selectedIDs.remove(user.uid) }
            else { multi.selectedIDs.insert(user.uid) }
        } label: {
            HStack(spacing: 12) {
                AsyncImage(url: user.avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.circle.fill").resizable().foregroundStyle(.blue)
                }
                .frame(width: 48, height: 48).clipShape(Circle())
                VStack(alignment: .leading) {
                    HStack {
                        Text(user.name).font(.headline)
                        if let status = multi.statuses[user.uid] {
                            HStack(spacing: 3) {
                                Image(systemName: status.icon)
                                Text(status.title)
                            }
                            .padding(4)
                            .font(.caption)
                            .foregroundStyle(status.color)
                            .background(status.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                            .accessibilityLabel(status.failureMessage.map { "\(status.title)：\($0)" } ?? status.title)
                        }
                    }
                    Text(masked(user.phoneNumber)).font(.subheadline).foregroundStyle(.secondary)
                    if let failure = multi.statuses[user.uid]?.failureMessage {
                        Text(failure).font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
                if isCurrent { Text("当前账号").font(.caption).foregroundStyle(.secondary) }
                Image(systemName: multi.selectedIDs.contains(user.uid) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(multi.isSigning)
    }

    private func masked(_ value: String) -> String {
        guard value.count >= 7 else { return value }
        return "\(value.prefix(3))****\(value.suffix(4))"
    }
}

struct MultiAccountToolbar: View {
    let model: AppModel
    @Bindable var multi: MultiAccountSign

    var body: some View {
        Button {
            multi.load(current: model.user)
            multi.isShowing = true
        } label: {
            Image(systemName: "person.2")
        }
        .accessibilityLabel("选择签到用户")
    }
}
