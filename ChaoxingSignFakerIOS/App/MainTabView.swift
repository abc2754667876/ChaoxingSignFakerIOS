import SwiftUI

struct MainTabView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            CourseListView(model: model)
                .tabItem {
                    Label("首页", systemImage: "house")
                }

            PlaceholderTabView(
                title: "多账号",
                systemImage: "person.2",
                description: "可在这里管理用于签到的其他账号。"
            )
            .tabItem {
                Label("多账号", systemImage: "person.2")
            }

            PlaceholderTabView(
                title: "位置",
                systemImage: "location",
                description: "可在这里管理常用签到位置。"
            )
            .tabItem {
                Label("位置", systemImage: "location")
            }

            ProfileView(model: model)
                .tabItem {
                    Label("我的", systemImage: "person")
                }
        }
    }
}

private struct PlaceholderTabView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )
            .navigationTitle(title)
        }
    }
}

private struct ProfileView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if let user = model.user {
                    Section("当前账号") {
                        LabeledContent("姓名", value: user.name)
                    }
                }

                Section {
                    Button("退出登录", role: .destructive) {
                        model.logout()
                    }
                }
            }
            .navigationTitle("我的")
        }
    }
}
