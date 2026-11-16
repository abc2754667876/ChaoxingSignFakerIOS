import SwiftUI

struct OrdinarySignView: View {
    private enum State: Equatable {
        case loading
        case ready
        case signing
        case success
        case alreadySigned
        case expired
        case failure(String)
    }

    let model: AppModel
    let activity: ChaoxingActivity
    @State private var state: State = .loading

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 54))
                .foregroundStyle(color)
            Text(activity.title)
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if state == .ready {
                Button("确认签到") {
                    Task { await sign() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if case .failure = state {
                Button("重新检查") {
                    Task { await prepare() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("普通签到")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
    }

    private var icon: String {
        switch state {
        case .loading, .signing: "hourglass"
        case .ready: "hand.tap"
        case .success: "checkmark.circle.fill"
        case .alreadySigned: "checkmark.seal.fill"
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
        case .ready: "活动允许普通点击签到。提交前请确认这是你的真实签到意图。"
        case .signing: "正在提交签到…"
        case .success: "签到成功"
        case .alreadySigned: "你已经签到过了"
        case .expired: "签到已截止"
        case .failure(let message): message
        }
    }

    private func prepare() async {
        state = .loading
        do {
            switch try await model.prepareOrdinarySign(activity) {
            case .ready: state = .ready
            case .alreadySigned: state = .alreadySigned
            case .expired: state = .expired
            }
        } catch {
            state = .failure(error.localizedDescription)
        }
    }

    private func sign() async {
        state = .signing
        do {
            _ = try await model.signOrdinary(activity)
            state = .success
        } catch let error as ChaoxingError {
            switch error {
            case .alreadySigned: state = .alreadySigned
            case .signExpired: state = .expired
            default: state = .failure(error.localizedDescription)
            }
        } catch {
            state = .failure(error.localizedDescription)
        }
    }
}
