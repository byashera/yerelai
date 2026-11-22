import AVFoundation
import SwiftUI
import UIKit

// MARK: - ChatGPT-Style Zero-Confirmation Instant Camera Sheet

struct InstantCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = InstantCameraController()
    let onCapture: (Data) -> Void
    var onOpenGallery: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if controller.isCameraAvailable {
                CameraPreviewLayerView(session: controller.session)
                    .ignoresSafeArea()
            } else {
                // Clean visual backdrop when previewed on iOS Simulator (no physical camera)
                LinearGradient(
                    colors: [Color(red: 0.06, green: 0.10, blue: 0.18), Color(red: 0.10, green: 0.15, blue: 0.26)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.white.opacity(0.65))
                    Text("Anlık Kamera Hazır")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Deklanşöre bastığında onay istemeden doğrudan sohbet kutusuna düşer.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            // Subtle viewfinder corner brackets
            ViewfinderCornersOverlay()
                .padding(.horizontal, 26)
                .padding(.vertical, 118)
                .allowsHitTesting(false)

            VStack {
                // Top Liquid Glass Bar
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(SenSpringButtonStyle())
                    .senGlassCircle(interactive: true)

                    Spacer()

                    Text("Anlık Çekim")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .senGlassCapsule(interactive: false)

                    Spacer()

                    Button {
                        SenHaptics.light()
                        controller.toggleFlash()
                    } label: {
                        Image(systemName: controller.flashEnabled ? "bolt.fill" : "bolt.slash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(controller.flashEnabled ? .yellow : .white)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(SenSpringButtonStyle())
                    .senGlassCircle(interactive: true)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                Spacer()

                // Bottom Instant Shutter Bar
                HStack(spacing: 36) {
                    Button {
                        SenHaptics.light()
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            onOpenGallery?()
                        }
                    } label: {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(SenSpringButtonStyle())
                    .senGlassCircle(interactive: true)
                    .accessibilityLabel("Galeriden Seç")

                    // Instant Shutter Button (Zero Confirmation!)
                    Button {
                        SenHaptics.medium()
                        controller.captureInstant { data in
                            if let data {
                                onCapture(data)
                                dismiss()
                            }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(.white, lineWidth: 4)
                                .frame(width: 74, height: 74)
                            Circle()
                                .fill(.white)
                                .frame(width: 60, height: 60)
                        }
                    }
                    .buttonStyle(SenSpringButtonStyle())
                    .accessibilityLabel("Fotoğraf Çek")

                    Button {
                        SenHaptics.light()
                        controller.flipCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(SenSpringButtonStyle())
                    .senGlassCircle(interactive: true)
                    .accessibilityLabel("Kamerayı Çevir")
                }
                .padding(.bottom, 28)
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }
}

private struct ViewfinderCornersOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let len: CGFloat = 24
            Path { p in
                // Top-left
                p.move(to: CGPoint(x: 0, y: len))
                p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: len, y: 0))
                // Top-right
                p.move(to: CGPoint(x: w - len, y: 0))
                p.addLine(to: CGPoint(x: w, y: 0))
                p.addLine(to: CGPoint(x: w, y: len))
                // Bottom-left
                p.move(to: CGPoint(x: 0, y: h - len))
                p.addLine(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: len, y: h))
                // Bottom-right
                p.move(to: CGPoint(x: w - len, y: h))
                p.addLine(to: CGPoint(x: w, y: h))
                p.addLine(to: CGPoint(x: w, y: h - len))
            }
            .stroke(.white.opacity(0.42), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

final class InstantCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    @Published var isCameraAvailable: Bool = false
    @Published var flashEnabled: Bool = false

    private let photoOutput = AVCapturePhotoOutput()
    private var currentPosition: AVCaptureDevice.Position = .back
    private var pendingCompletion: ((Data?) -> Void)?

    func start() {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition) != nil else {
            isCameraAvailable = false
            return
        }
        isCameraAvailable = true
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self, granted else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                self.configureSession()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }
    }

    func stop() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func toggleFlash() {
        flashEnabled.toggle()
    }

    func flipCamera() {
        currentPosition = (currentPosition == .back) ? .front : .back
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.configureSession()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        for inp in session.inputs { session.removeInput(inp) }
        if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentPosition),
           let input = try? AVCaptureDeviceInput(device: dev),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
    }

    func captureInstant(completion: @escaping (Data?) -> Void) {
        guard isCameraAvailable, session.isRunning else {
            completion(nil)
            return
        }
        pendingCompletion = completion
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(flashEnabled ? .on : .off) {
            settings.flashMode = flashEnabled ? .on : .off
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let rawData = photo.fileDataRepresentation()
        // Compress slightly for fast LAN/Cloudflare multimodal upload while keeping crisp detail
        let compressed: Data?
        if let rawData, let img = UIImage(data: rawData) {
            compressed = img.jpegData(compressionQuality: 0.78)
        } else {
            compressed = rawData
        }
        DispatchQueue.main.async { [weak self] in
            self?.pendingCompletion?(compressed)
            self?.pendingCompletion = nil
        }
    }
}

struct CameraPreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
