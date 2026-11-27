@preconcurrency import AVFoundation
import SwiftUI

struct SignQRScanner: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {
        controller.onScan = onScan
    }
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "sign.qr.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var didScan = false
    private var isVisible = false
    private var permissionTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isVisible = true
        permissionTask = Task { @MainActor in
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard !Task.isCancelled, isVisible else { return }
            guard granted else {
                showMessage("请在系统设置中允许相机权限后重试", allowsSettings: true)
                return
            }
            // Configure, start, and stop on one queue. Dismissing the sheet while
            // permission is pending must never start the camera afterwards.
            let output = AVCaptureMetadataOutput()
            output.setMetadataObjectsDelegate(self, queue: .main)
            captureQueue.async { [self] in
                if session.inputs.isEmpty {
                    guard let device = AVCaptureDevice.default(for: .video),
                          let input = try? AVCaptureDeviceInput(device: device),
                          session.canAddInput(input) else {
                        reportUnavailable()
                        return
                    }
                    session.beginConfiguration()
                    session.addInput(input)
                    guard session.canAddOutput(output) else {
                        session.removeInput(input)
                        session.commitConfiguration()
                        reportUnavailable()
                        return
                    }
                    session.addOutput(output)
                    guard output.availableMetadataObjectTypes.contains(.qr) else {
                        session.removeOutput(output)
                        session.removeInput(input)
                        session.commitConfiguration()
                        reportUnavailable()
                        return
                    }
                    output.metadataObjectTypes = [.qr]
                    session.commitConfiguration()
                }
                session.startRunning()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isVisible = false
        permissionTask?.cancel()
        captureQueue.async { [session] in session.stopRunning() }
    }

    private func reportUnavailable() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible else { return }
            self.showMessage("无法使用相机，请在配备相机的设备上重试", allowsSettings: false)
        }
    }

    private func showMessage(_ text: String, allowsSettings: Bool) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        let stack = UIStackView(arrangedSubviews: [label])
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        if allowsSettings {
            let button = UIButton(type: .system)
            button.setTitle("前往设置", for: .normal)
            button.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    @objc private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard isVisible, !didScan,
              let value = metadataObjects.compactMap({ ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }).first else { return }
        didScan = true
        captureQueue.async { [session] in session.stopRunning() }
        onScan?(value)
    }
}
