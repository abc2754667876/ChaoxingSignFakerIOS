import SwiftUI

struct LoginView: View {
    @Bindable var model: AppModel
    @State private var phoneNumber = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("手机号或账号", text: $phoneNumber)
                        .textContentType(.username)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("学习通账号")
                }

                if let error = model.loginError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await model.login(phoneNumber: phoneNumber, password: password) }
                    } label: {
                        ZStack {
                            Capsule()
                                .fill(.blue)
                                .frame(height: 48)
                            
                            if model.isLoggingIn {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("登录")
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .disabled(model.isLoggingIn || phoneNumber.isEmpty || password.isEmpty)
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("登录")
        }
    }
}

