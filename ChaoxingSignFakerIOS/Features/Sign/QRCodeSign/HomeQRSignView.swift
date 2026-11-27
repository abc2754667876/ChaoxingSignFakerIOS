import SwiftUI

struct HomeQRSignView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var scannedValue: String?
    @State private var destination: Destination?
    @State private var errorMessage: String?

    private struct Destination {
        let activity: ChaoxingActivity
        let code: ParsedSignQRCode
    }

    var body: some View {
        NavigationStack {
            Group {
                if let destination {
                    CodeSignView(model: model, activity: destination.activity, mode: .qrCode,
                                 initialQRCode: destination.code)
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("无法使用此二维码", systemImage: "qrcode")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("重新扫描") {
                            self.errorMessage = nil
                            scannedValue = nil
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if scannedValue != nil {
                    ProgressView("正在查找签到活动…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SignQRScanner { value in
                        guard scannedValue == nil else { return }
                        scannedValue = value
                    }
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .bottom) {
                        Text("将教师展示的签到二维码放入镜头内")
                            .font(.subheadline)
                            .padding()
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 32)
                            .allowsHitTesting(false)
                    }
                }
            }
            .navigationTitle(destination == nil ? "扫描签到二维码" : "二维码签到")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(destination == nil ? "取消" : "关闭") { dismiss() }
                }
            }
            .task(id: scannedValue) {
                guard let scannedValue else { return }
                let uid = model.user?.uid
                do {
                    let code = try ParsedSignQRCode(scannedValue)
                    let activity = try await model.activity(for: code)
                    try Task.checkCancellation()
                    guard model.user?.uid == uid else { return }
                    destination = Destination(activity: activity, code: code)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled, model.user?.uid == uid else { return }
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
