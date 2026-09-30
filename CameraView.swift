import SwiftUI
import AppKit
import AVFoundation
import CoreImage
import Combine

/// A normal titled window (like `DebugStatsWindowController`) hosting a live camera
/// "mirror" — search "camera" in the launcher to open it (see `SearchEngine`).
@MainActor
final class CameraWindowController: NSObject, NSWindowDelegate {
    static let shared = CameraWindowController()

    private var window: NSWindow?
    private let capture = CameraCaptureController()

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
        } else {
            let hosting = NSHostingController(rootView: CameraView(capture: capture))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Camera"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            newWindow.center()
            window = newWindow
            newWindow.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        capture.start()
    }

    func windowWillClose(_ notification: Notification) {
        // Only pay for a running capture session while the window is actually open —
        // same reasoning as `ResourceMonitor.stopSampling` in `DebugStatsWindowController`.
        capture.stop()
    }
}

/// Owns the `AVCaptureSession` and publishes each frame — already mirrored, like looking
/// in an actual mirror — as an `NSImage` for `CameraView` to display. Also doubles as the
/// source of truth for "what you'd copy/save right now", so the copy/save actions always
/// match exactly what's on screen.
@MainActor
final class CameraCaptureController: NSObject, ObservableObject {
    @Published private(set) var previewImage: NSImage?
    @Published private(set) var permissionDenied = false
    @Published private(set) var noCameraAvailable = false

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.reflow.camera.session")
    private let ciContext = CIContext()
    private var isConfigured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            beginRunning()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.beginRunning()
                    } else {
                        self.permissionDenied = true
                    }
                }
            }
        case .denied, .restricted:
            permissionDenied = true
        @unknown default:
            permissionDenied = true
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func beginRunning() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                guard self.configureSession() else { return }
                self.isConfigured = true
            }
            self.session.startRunning()
        }
    }

    /// Must run on `sessionQueue`. Returns `false` (having already reported the failure
    /// back on the main thread) if no camera is available to configure.
    private func configureSession() -> Bool {
        guard let device = AVCaptureDevice.default(for: .video) else {
            DispatchQueue.main.async { [weak self] in self?.noCameraAvailable = true }
            return false
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            DispatchQueue.main.async { [weak self] in self?.noCameraAvailable = true }
            return false
        }

        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        if session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
        return true
    }
}

extension CameraCaptureController: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// Called on `sessionQueue`, never the main thread — per Apple's guidance for
    /// `AVCaptureVideoDataOutput`'s delegate, since decoding each frame here is real work
    /// and blocking the main thread with it would stall the whole app.
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        // Flip horizontally so this behaves like an actual mirror (and like Photo Booth/
        // FaceTime's front-camera preview) instead of showing the raw, "backwards" feed.
        let mirrored = source.transformed(by: CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -source.extent.width, y: 0))

        Task { @MainActor [weak self] in
            guard let self, let cgImage = self.ciContext.createCGImage(mirrored, from: mirrored.extent) else { return }
            self.previewImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
    }
}

/// The live self-view itself. ⌘C copies whatever's currently on screen to the clipboard;
/// Return saves it to the Desktop as a PNG — both act on the exact same mirrored frame
/// `CameraCaptureController` is already displaying, so what you see is what you get.
struct CameraView: View {
    @ObservedObject var capture: CameraCaptureController
    @FocusState private var isFocused: Bool
    @State private var feedback: String?

    var body: some View {
        ZStack {
            Color.black

            if capture.permissionDenied {
                statusMessage(
                    title: "Camera Access Denied",
                    detail: "Enable it in System Settings → Privacy & Security → Camera, then reopen this window."
                )
            } else if capture.noCameraAvailable {
                statusMessage(
                    title: "No Camera Found",
                    detail: "Connect or enable a camera and reopen this window."
                )
            } else if let image = capture.previewImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 480, height: 360)
                    .clipped()
            } else {
                ProgressView("Starting camera…")
                    .foregroundStyle(.white)
            }

            if let feedback {
                Text(feedback)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .frame(width: 480, height: 360)
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.return) {
            saveToDesktop()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "c"), phases: [.down]) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            copyToClipboard()
            return .handled
        }
    }

    private func statusMessage(title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private func copyToClipboard() {
        guard let image = capture.previewImage else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        showFeedback("Copied")
    }

    private func saveToDesktop() {
        guard let image = capture.previewImage, let data = image.pngData() else { return }

        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        let url = desktop.appendingPathComponent("Camera Photo \(formatter.string(from: Date())).png")

        do {
            try data.write(to: url)
            showFeedback("Saved to Desktop")
        } catch {
            showFeedback("Couldn't save: \(error.localizedDescription)")
        }
    }

    private func showFeedback(_ text: String) {
        feedback = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if feedback == text {
                feedback = nil
            }
        }
    }
}

#Preview {
    CameraView(capture: CameraCaptureController())
}
