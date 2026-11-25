import SwiftUI

struct OrdinarySignView: View {
    private enum State: Equatable {
        case loading, ready, signing, success, alreadySigned, expired
        case failure(String)
    }

    private enum UserSignStatus: Equatable {
        case signing, success, alreadySigned, expired
        case failure(String)

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

    let model: AppModel
    let activity: ChaoxingActivity
    private let store = OtherUserStore()

    @State private var state: State = .loading
    @State private var hasPrepared = false
    @State private var showUserChoose = false
    @State private var accounts: [OtherUserAccount] = []
    @State private var selectedUserIDs: Set<Int> = []
    @State private var completedUserIDs: Set<Int> = []
    @State private var userStatuses: [Int: UserSignStatus] = [:]

    private var currentUser: ChaoxingUser? { model.user }
    private var otherAccounts: [OtherUserAccount] {
        var seen = Set<Int>()
        if let currentUser { seen.insert(currentUser.uid) }
        return accounts.filter { seen.insert($0.session.user.uid).inserted }
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .resizable().scaledToFit().frame(width: 64, height: 64)
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))
            Text("普通签到").font(.largeTitle)
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: performButtonAction) {
                ZStack {
                    Capsule().fill(color).frame(height: 48)
                    if isProcessing { ProgressView().tint(.white) }
                    else { Text(buttonTitle).foregroundStyle(.white) }
                }
            }
            .disabled(!canPerformButtonAction)
            .padding(.top, 72)
        }
        .padding(.horizontal)
        .navigationTitle("普通签到")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { accounts = store.load(); showUserChoose = true } label: {
                    Image(systemName: "person.2")
                }
                .accessibilityLabel("选择签到用户")
            }
        }
        .sheet(isPresented: $showUserChoose) { userChoose }
        .task {
            accounts = store.load()
            if let currentUser { selectedUserIDs.insert(currentUser.uid) }
            await prepare()
        }
        .animation(.default, value: state)
    }

    private var userChoose: some View {
        NavigationStack {
            List {
                Section("用户列表") {
                    if let currentUser { userRow(currentUser, isCurrent: true) }
                    ForEach(otherAccounts) { account in
                        userRow(account.session.user, isCurrent: false)
                    }
                }
            }
            .navigationTitle("选择需要签到的用户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showUserChoose = false } } }
        }
    }

    private func userRow(_ user: ChaoxingUser, isCurrent: Bool) -> some View {
        Button {
            if selectedUserIDs.contains(user.uid) { selectedUserIDs.remove(user.uid) }
            else { selectedUserIDs.insert(user.uid) }
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
                        if let status = userStatuses[user.uid] {
                            HStack(spacing: 3) {
                                Image(systemName: status.icon)
                                Text(status.title)
                            }
                            .padding(4)
                            .foregroundStyle(status.color)
                            .font(.caption)
                            .background(status.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                            .accessibilityLabel(status.failureMessage.map { "\(status.title)：\($0)" } ?? status.title)
                        }
                    }

                    Text(masked(user.phoneNumber)).font(.subheadline).foregroundStyle(.secondary)
                    if let failure = userStatuses[user.uid]?.failureMessage {
                        Text(failure).font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer()
                if isCurrent { Text("当前账号").font(.caption).foregroundStyle(.secondary) }
                Image(systemName: selectedUserIDs.contains(user.uid) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state == .signing)
    }

    private func masked(_ value: String) -> String {
        guard value.count >= 7 else { return value }
        return "\(value.prefix(3))****\(value.suffix(4))"
    }

    private var icon: String {
        switch state {
        case .loading, .signing: "hourglass"
        case .ready: activity.kind.systemImage
        case .success, .alreadySigned: "checkmark.circle.fill"
        case .expired: "clock.badge.xmark"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .success, .alreadySigned: .green
        case .expired, .failure: .orange
        default: .accentColor
        }
    }

    private var message: String {
        switch state {
        case .loading: "正在检查活动状态与签到要求…"
        case .ready: "选择账号后点击下方按钮签到"
        case .signing: "正在逐个提交签到…"
        case .success: "所选账号处理完成"
        case .alreadySigned: "当前账号已签到，可选择其他账号签到"
        case .expired: "签到已截止"
        case .failure(let text): text
        }
    }

    private var isProcessing: Bool { state == .loading || state == .signing }

    private var pendingUserIDs: Set<Int> {
        let availableIDs = Set(otherAccounts.map { $0.session.user.uid })
            .union(currentUser.map { [$0.uid] } ?? [])
        return selectedUserIDs.intersection(availableIDs).subtracting(completedUserIDs)
    }

    private var canPerformButtonAction: Bool {
        guard !pendingUserIDs.isEmpty else { return false }
        return switch state {
        case .ready, .alreadySigned, .success, .failure: true
        case .loading, .signing, .expired: false
        }
    }

    private var buttonTitle: String {
        switch state {
        case .ready, .alreadySigned: "确认签到"
        case .success: "继续签到"
        case .failure: hasPrepared ? "重试签到" : "重新检查"
        case .expired: "签到已截止"
        case .loading, .signing: ""
        }
    }

    private func performButtonAction() {
        guard canPerformButtonAction else { return }
        Task { if hasPrepared { await sign() } else { await prepare() } }
    }

    private func updateState(_ newState: State) {
        withAnimation { state = newState }
    }

    private func prepare() async {
        hasPrepared = false
        updateState(.loading)
        do {
            switch try await model.prepareOrdinarySign(activity) {
            case .ready:
                hasPrepared = true
                updateState(.ready)
            case .alreadySigned:
                hasPrepared = true
                if let currentUser {
                    completedUserIDs.insert(currentUser.uid)
                    userStatuses[currentUser.uid] = .alreadySigned
                }
                updateState(.alreadySigned)
            case .expired:
                hasPrepared = true
                updateState(.expired)
            }
        } catch { updateState(.failure(error.localizedDescription)) }
    }

    private func sign() async {
        let targets = pendingUserIDs
        updateState(.signing)
        var failures = 0
        if let currentUser, targets.contains(currentUser.uid) {
            userStatuses[currentUser.uid] = .signing
            do {
                _ = try await model.signOrdinary(activity)
                completedUserIDs.insert(currentUser.uid)
                userStatuses[currentUser.uid] = .success
            } catch let error as ChaoxingError {
                switch error {
                case .alreadySigned:
                    completedUserIDs.insert(currentUser.uid)
                    userStatuses[currentUser.uid] = .alreadySigned
                case .signExpired:
                    userStatuses[currentUser.uid] = .expired
                    updateState(.expired)
                    return
                default:
                    failures += 1
                    userStatuses[currentUser.uid] = .failure(error.localizedDescription)
                }
            } catch {
                failures += 1
                userStatuses[currentUser.uid] = .failure(error.localizedDescription)
            }
        }
        for account in otherAccounts where targets.contains(account.session.user.uid) {
            let user = account.session.user
            userStatuses[user.uid] = .signing
            do {
                let preparation = try await model.signOrdinary(activity, for: account)
                completedUserIDs.insert(user.uid)
                switch preparation {
                case .ready: userStatuses[user.uid] = .success
                case .alreadySigned: userStatuses[user.uid] = .alreadySigned
                case .expired: userStatuses[user.uid] = .expired
                }
            } catch let error as ChaoxingError {
                switch error {
                case .alreadySigned:
                    completedUserIDs.insert(user.uid)
                    userStatuses[user.uid] = .alreadySigned
                case .signExpired:
                    completedUserIDs.insert(user.uid)
                    userStatuses[user.uid] = .expired
                default:
                    failures += 1
                    userStatuses[user.uid] = .failure(error.localizedDescription)
                }
            } catch {
                failures += 1
                userStatuses[user.uid] = .failure(error.localizedDescription)
            }
        }
        if failures > 0 { updateState(.failure("部分账号签到失败，可重试")) }
        else { updateState(.success) }
    }
}
