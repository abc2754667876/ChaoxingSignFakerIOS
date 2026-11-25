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
    
    @State private var showUserChoose = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundStyle(color)
                .contentTransition(.symbolEffect(.replace))

            Text("普通签到")
                .font(.largeTitle)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // TODO: 若选择了多账号，为选中的账号进行签到（如果当前主账号没被选中，则主账号不用签到）
            Button(action: performButtonAction) {
                ZStack {
                    Capsule()
                        .fill(color)
                        .frame(height: 48)
                    if isProcessing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(buttonTitle)
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(!canPerformButtonAction)
            .padding(.top, 72)
        }
        .padding(.horizontal)
        .navigationTitle("普通签到")
        .navigationBarTitleDisplayMode(.inline)
        .task { await prepare() }
        .animation(.default, value: state)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showUserChoose = true
                }) {
                    Image("custom.list.bullet.badge.person.crop")
                }
            }
        }
        .sheet(isPresented: $showUserChoose) {
            userChoose
        }
    }
    
    private var userChoose: some View {
        NavigationStack {
            List {
                Section(header: Text("用户列表")) {
                    HStack { // TODO: 每个数据项整一行都可以点击，点击为选择/取消选择操作
                        Image(systemName: "person.circle.fill") // TODO: 这里显示头像
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .foregroundStyle(.blue.gradient)
                        
                        VStack(alignment: .leading) {
                            Text("张诚志") // TODO: 这里显示姓名
                                .font(.headline)
                            Text("155****2754") // TODO: 这里显示脱敏后手机号
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill") // TODO: 选中后改为checkmark.circle.fill，未选中为circle
                    } // TODO: List里第一行必须是当前账号，且默认选中，多账号页面中可能存在与当前账号重复的情况，本List中注意去重
                    
                    // TODO: 接下来加载多账号里存储的其他账号，注意去重
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .foregroundStyle(.blue.gradient)
                        
                        VStack(alignment: .leading) {
                            Text("董昊宇")
                                .font(.headline)
                            Text("136****9955")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "circle")
                    }
                }
            }
            .navigationTitle("选择需要签到的用户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("关闭") { showUserChoose = false } } }
        }
    }

    private var icon: String {
        switch state {
        case .loading, .signing: "hourglass"
        case .ready: activity.kind.systemImage
        case .success: "checkmark.circle.fill"
        case .alreadySigned: "checkmark.circle.fill"
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
        case .ready: "点击下方按钮签到"
        case .signing: "正在提交签到…"
        case .success: "签到成功"
        case .alreadySigned: "你已经签到过了"
        case .expired: "签到已截止"
        case .failure(let message): message
        }
    }

    private var isProcessing: Bool {
        state == .loading || state == .signing
    }

    private var canPerformButtonAction: Bool {
        switch state {
        case .ready, .failure: true
        case .loading, .signing, .success, .alreadySigned, .expired: false
        }
    }

    private var buttonTitle: String {
        switch state {
        case .ready: "确认签到"
        case .success, .alreadySigned: "已签到"
        case .expired: "签到已截止"
        case .failure: "重新检查"
        case .loading, .signing: ""
        }
    }

    private func performButtonAction() {
        switch state {
        case .ready:
            Task { await sign() }
        case .failure:
            Task { await prepare() }
        case .loading, .signing, .success, .alreadySigned, .expired:
            break
        }
    }

    private func updateState(_ newState: State) {
        withAnimation {
            state = newState
        }
    }

    private func prepare() async {
        updateState(.loading)
        do {
            switch try await model.prepareOrdinarySign(activity) {
            case .ready: updateState(.ready)
            case .alreadySigned: updateState(.alreadySigned)
            case .expired: updateState(.expired)
            }
        } catch {
            updateState(.failure(error.localizedDescription))
        }
    }

    private func sign() async {
        updateState(.signing)
        do {
            _ = try await model.signOrdinary(activity)
            updateState(.success)
        } catch let error as ChaoxingError {
            switch error {
            case .alreadySigned: updateState(.alreadySigned)
            case .signExpired: updateState(.expired)
            default: updateState(.failure(error.localizedDescription))
            }
        } catch {
            updateState(.failure(error.localizedDescription))
        }
    }
}
