import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        if model.user == nil {
            LoginView(model: model)
        } else {
            MainTabView(model: model)
                .task {
                    if model.courses.isEmpty {
                        await model.refreshHome()
                    }
                }
        }
    }
}

#Preview {
    ContentView()
}
