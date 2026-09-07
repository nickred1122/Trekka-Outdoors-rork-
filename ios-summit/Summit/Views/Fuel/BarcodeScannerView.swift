import AVFoundation
import SwiftUI
import UIKit

/// What the camera is currently able to do.
nonisolated enum BarcodeScannerState: Equatable, Sendable {
    case starting
    case scanning
    /// Camera access was refused, which only Settings can undo.
    case denied
    /// No camera on this device at all — distinct from access being refused,
    /// because the fix is completely different.
    case unavailable
}

/// Reads a barcode off a packet using the camera.
///
/// A plain capture session with a metadata output rather than a higher-level
/// scanner, so the device list can include an external camera as well as the
/// built-in ones.
struct BarcodeScannerView: View {
    var onScan: (String) -> Void
    var onManualEntry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state: BarcodeScannerState = .starting
    @State private var lastCode: String?
    @State private var feedback = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                BarcodeCameraView(state: $state) { code in
                    guard lastCode == nil else { return }
                    lastCode = code
                    feedback += 1
                    onScan(code)
                    dismiss()
                }
                .ignoresSafeArea()

                switch state {
                case .starting, .scanning:
                    reticle
                case .denied:
                    message(
                        symbol: "lock.fill",
                        title: "Camera access is off",
                        detail: "Turn on the camera for Trekka in Settings to scan barcodes, or add the food by hand.",
                        action: "Open Settings",
                        handler: openSettings
                    )
                case .unavailable:
                    message(
                        symbol: "camera.fill",
                        title: "No camera available",
                        detail: "This device has no camera to scan with. You can still add the food by hand.",
                        action: nil,
                        handler: nil
                    )
                }
            }
            .navigationTitle("Scan barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .tint(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("By hand") {
                        onManualEntry()
                        dismiss()
                    }
                    .tint(Theme.accent)
                }
            }
            .sensoryFeedback(.success, trigger: feedback)
        }
        .preferredColorScheme(.dark)
    }

    /// The frame to hold the barcode in, plus a line that sweeps it so the
    /// screen reads as live rather than frozen.
    private var reticle: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                    .frame(height: 170)

                if state == .scanning {
                    ScanSweep()
                        .frame(height: 170)
                }
            }
            .padding(.horizontal, 34)

            Text(state == .starting ? "Starting camera…" : "Line the barcode up inside the frame")
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 40)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    private func message(
        symbol: String,
        title: String,
        detail: String,
        action: String?,
        handler: (() -> Void)?
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.accent)

            Text(title)
                .font(.system(.headline, weight: .bold))
                .foregroundStyle(.white)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)

            if let action, let handler {
                Button(action, action: handler)
                    .font(.system(.subheadline, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .padding(.top, 4)
            }
        }
        .padding(28)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// A line travelling up and down the reticle while the camera is live.
private struct ScanSweep: View {
    @State private var isDown = false

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Theme.accent.opacity(0), Theme.accent, Theme.accent.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .offset(y: isDown ? geometry.size.height - 2 : 0)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: isDown)
        }
        .onAppear { isDown = true }
    }
}

// MARK: - Capture session

private struct BarcodeCameraView: UIViewControllerRepresentable {
    @Binding var state: BarcodeScannerState
    var onScan: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeCameraController {
        let controller = BarcodeCameraController()
        controller.onScan = onScan
        controller.onState = { newState in state = newState }
        return controller
    }

    func updateUIViewController(_ controller: BarcodeCameraController, context: Context) {
        controller.onScan = onScan
        controller.onState = { newState in state = newState }
    }
}

/// Runs the capture session and reports the first barcode it reads.
final class BarcodeCameraController: UIViewController {
    var onScan: ((String) -> Void)?
    var onState: ((BarcodeScannerState) -> Void)?

    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    /// Session configuration and start/stop are blocking, so they stay off the
    /// main thread; only the state callbacks come back to it.
    private let sessionQueue = DispatchQueue(label: "trekka.barcode.session")
    private var hasDelivered = false

    /// The formats found on packaged food. UPC-A arrives as EAN-13, which is
    /// why there is no separate case for it.
    private static let symbologies: [AVMetadataObject.ObjectType] = [
        .ean13, .ean8, .upce, .code128, .code39, .code93, .itf14, .interleaved2of5,
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func requestAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted {
                        configure()
                    } else {
                        onState?(.denied)
                    }
                }
            }
        default:
            onState?(.denied)
        }
    }

    private func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            // `.external` covers a camera attached to the device rather than
            // built into it, which is how a Mac or a cloud simulator presents one.
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [
                    .builtInWideAngleCamera,
                    .builtInDualCamera,
                    .builtInDualWideCamera,
                    .builtInTripleCamera,
                    .external,
                ],
                mediaType: .video,
                position: .unspecified
            )
            guard let device = discovery.devices.first,
                  let input = try? AVCaptureDeviceInput(device: device) else {
                Task { @MainActor [weak self] in self?.onState?(.unavailable) }
                return
            }

            session.beginConfiguration()
            session.sessionPreset = .high
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                Task { @MainActor [weak self] in self?.onState?(.unavailable) }
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                Task { @MainActor [weak self] in self?.onState?(.unavailable) }
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            // Only the symbologies the device actually supports can be set;
            // asking for one it does not have raises an exception.
            let supported = Set(output.availableMetadataObjectTypes)
            output.metadataObjectTypes = Self.symbologies.filter { supported.contains($0) }
            session.commitConfiguration()

            session.startRunning()

            Task { @MainActor [weak self] in
                guard let self else { return }
                attachPreview()
                onState?(.scanning)
            }
        }
    }

    private func attachPreview() {
        guard preview == nil else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        preview = layer
    }
}

extension BarcodeCameraController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasDelivered else { return }
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return }

        hasDelivered = true
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        onScan?(value)
    }
}
