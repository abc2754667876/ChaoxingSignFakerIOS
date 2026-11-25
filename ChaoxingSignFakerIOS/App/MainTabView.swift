import SwiftUI

struct MainTabView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            HomeView(model: model)
                .tabItem {
                    Label("首页", systemImage: "house")
                }

            OtherUsersView(currentUser: model.user)
            .tabItem {
                Label("多账号", systemImage: "person.2")
            }

            LocationView()
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
