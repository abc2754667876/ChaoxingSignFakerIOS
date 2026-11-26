import SwiftUI

private enum SignVerificationRequest: Identifiable {
    case face(FaceSignCoordinator.Request)
    case captcha(CaptchaCoordinator.Request)

    var id: UUID {
        switch self {
        case .face(let request): request.id
        case .captcha(let request): request.id
        }
    }
}

private struct SignVerificationSupport: ViewModifier {
    let model: AppModel
    let activity: ChaoxingActivity
    @State private var presented: SignVerificationRequest?

    private var request: Binding<SignVerificationRequest?> {
        Binding {
            if let face = model.faceSign.request, face.activityID == activity.id { return .face(face) }
            if let captcha = model.captcha.request, captcha.activity.id == activity.id { return .captcha(captcha) }
            return nil
        } set: { value in
            guard value == nil else { return }
            switch presented {
            case .face(let request):
                if model.faceSign.request?.id == request.id { model.faceSign.request = nil }
            case .captcha(let request):
                if model.captcha.request?.id == request.id { model.captcha.request = nil }
            case nil: break
            }
        }
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: request, onDismiss: {
                let previous = presented
                presented = nil
                switch previous {
                case .face(let request): model.faceSign.dismissSelection(requestID: request.id)
                case .captcha(let request): model.captcha.dismiss(requestID: request.id)
                case nil: break
                }
            }) { request in
                Group {
                    switch request {
                    case .face(let request): FaceSignPhotoView(request: request, coordinator: model.faceSign)
                    case .captcha(let request): CaptchaView(request: request, coordinator: model.captcha)
                    }
                }
                .onAppear { presented = request }
            }
            .onAppear {
                model.faceSign.activate(activityID: activity.id)
                model.captcha.activate(activityID: activity.id)
            }
            .onDisappear {
                model.faceSign.reset(activityID: activity.id)
                model.captcha.reset(activityID: activity.id)
            }
    }
}

extension View {
    func signVerificationSupport(model: AppModel, activity: ChaoxingActivity) -> some View {
        modifier(SignVerificationSupport(model: model, activity: activity))
    }
}
