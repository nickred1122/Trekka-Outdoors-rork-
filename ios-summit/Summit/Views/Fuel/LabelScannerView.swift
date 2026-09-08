import AVFoundation
import SwiftUI
import UIKit
import Vision

/// Reads the nutrition panel on a packet with the camera.
///
/// Unlike a barcode, a nutrition panel rarely resolves in a single frame: the
/// phone moves, the packet curves, and half the table comes back sharp while the
/// other half does not. So readings are merged as they arrive and the athlete is
/// shown exactly which lines have been found so far, rather than being left
/// pointing the camera at a packet with no idea whether it is working.
///
/// Nothing here is trusted blindly — the scan ends on a form with every value
/// filled in and editable, because a misread digit is silent otherwise.
struct LabelScannerView: View {
    var onRead: (NutritionLabelReading) -> Void
    var onManualEntry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state: BarcodeScannerState = .starting
    @State private var reading = NutritionLabelReading()
    @State private var hasFinished = false
    @State private var feedback = 0

    /// The lines worth reporting progress on. Serving is deliberately excluded:
    /// a European panel has no serving size and would look permanently unfinished.
    private static let tracked: [LabelField] = [.energy, .protein, .carbohydrate, .fat]

    private var foundCount: Int {
        Self.tracked.filter(reading.found.contains).count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                LabelCameraView(state: $state) { lines in
                    guard !hasFinished else { return }
                    let parsed = NutritionLabelParser.parse(lines: lines)
                    let merged = reading.merging(parsed)
                    guard merged != reading else { return }
                    withAnimation(.snappy(duration: 0.25)) { reading = merged }
                    if merged.isUsable { feedback += 1 }
                }
                .ignoresSafeArea()

                switch state {
                case .starting, .scanning:
                    scanningOverlay
                case .denied:
                    message(
                        symbol: "lock.fill",
                        title: "Camera access is off",
                        detail: "Turn on the camera for Trekka in Settings to read nutrition labels, or add the food by hand.",
                        action: "Open Settings",
                        handler: openSettings
                    )
                case .unavailable:
                    message(
                        symbol: "camera.fill",
                        title: "No camera available",
                        detail: "This device has no camera to read a label with. You can still add the food by hand.",
                        action: nil,
                        handler: nil
                    )
                }
            }
            .navigationTitle("Scan nutrition label")
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
            .sensoryFeedback(.increase, trigger: feedback)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Overlay

    private var scanningOverlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                .frame(height: 260)
                .overlay(alignment: .top) {
                    Text(state == .starting ? "Starting camera…" : "Fill the frame with the nutrition table")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.55), in: .capsule)
                        .offset(y: -14)
                }
                .padding(.horizontal, 24)

            Spacer(minLength: 0)

            panel
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
    }

    private var panel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Self.tracked) { field in
                    fieldPill(field)
                }
            }

            if reading.found.contains(.serving), let serving = reading.servingGrams {
                detailLine("Serving \(Int(serving.rounded())) \(reading.isLiquid ? "ml" : "g") · reading \(reading.basis.title)")
            } else {
                detailLine("Reading \(reading.basis.title)")
            }

            // A panel read per serving is unusable without the serving weight,
            // and saying so beats handing back numbers scaled by a guess.
            if reading.basis == .perServing && reading.servingGrams == nil && reading.isUsable {
                warning("Found the values but not the serving size — you'll be asked for it on the next screen.")
            } else if reading.energyAgreesWithMacros == false {
                warning("The calories and the macros don't quite add up. Check them on the next screen.")
            }

            Button {
                finish()
            } label: {
                Text(reading.isUsable ? "Use these values" : "Looking for the panel…")
                    .font(.system(.headline, weight: .bold))
                    .foregroundStyle(reading.isUsable ? Theme.canvas : .white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        reading.isUsable ? Theme.accent : Color.white.opacity(0.12),
                        in: .rect(cornerRadius: 13)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!reading.isUsable)
        }
        .padding(14)
        .background(.black.opacity(0.72), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }

    private func fieldPill(_ field: LabelField) -> some View {
        let isFound = reading.found.contains(field)
        return VStack(spacing: 4) {
            Image(systemName: isFound ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isFound ? Theme.positive : .white.opacity(0.35))
            Text(field.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isFound ? .white : .white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            (isFound ? Theme.positive.opacity(0.14) : Color.white.opacity(0.06)),
            in: .rect(cornerRadius: 10)
        )
    }

    private func detailLine(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.55))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.highlight)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(Theme.highlight.opacity(0.14), in: .rect(cornerRadius: 9))
    }

    private func finish() {
        guard !hasFinished, reading.isUsable else { return }
        hasFinished = true
        onRead(reading)
        dismiss()
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

// MARK: - Capture session

private struct LabelCameraView: UIViewControllerRepresentable {
    @Binding var state: BarcodeScannerState
    var onLines: ([String]) -> Void

    func makeUIViewController(context: Context) -> LabelCameraController {
        let controller = LabelCameraController()
        controller.onLines = onLines
        controller.onState = { newState in state = newState }
        return controller
    }

    func updateUIViewController(_ controller: LabelCameraController, context: Context) {
        controller.onLines = onLines
        controller.onState = { newState in state = newState }
    }
}

/// Runs the camera and hands recognised text back a few times a second.
final class LabelCameraController: UIViewController {
    var onLines: (([String]) -> Void)?
    var onState: ((BarcodeScannerState) -> Void)?

    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private let sessionQueue = DispatchQueue(label: "trekka.label.session")
    /// Text recognition is far heavier than barcode detection, so frames are
    /// handled on their own queue and dropped freely while one is in flight.
    private let visionQueue = DispatchQueue(label: "trekka.label.vision", qos: .userInitiated)
    private var reader: LabelFrameReader?

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
        reader?.stop()
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
            // Text needs resolution: a nutrition panel's smallest line is a few
            // pixels tall at anything less.
            session.sessionPreset = .hd1920x1080
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                Task { @MainActor [weak self] in self?.onState?(.unavailable) }
                return
            }
            session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            guard session.canAddOutput(output) else {
                session.commitConfiguration()
                Task { @MainActor [weak self] in self?.onState?(.unavailable) }
                return
            }
            session.addOutput(output)

            // A built-in camera is mounted on its side, so its frames need
            // rotating before text is upright. An external camera — which is how
            // a webcam is presented — is already the right way up.
            let orientation: CGImagePropertyOrientation = device.deviceType == .external ? .up : .right
            let reader = LabelFrameReader(orientation: orientation) { [weak self] lines in
                Task { @MainActor [weak self] in self?.onLines?(lines) }
            }
            self.reader = reader
            output.setSampleBufferDelegate(reader, queue: visionQueue)

            session.commitConfiguration()

            if let connection = output.connection(with: .video), device.deviceType != .external {
                connection.isVideoMirrored = false
            }

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

/// Recognises text on camera frames.
///
/// Lives outside the main actor because frames arrive on a capture queue. Its
/// small amount of mutable state is guarded by a lock, which is why the
/// unchecked conformance is sound.
private final class LabelFrameReader: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let orientation: CGImagePropertyOrientation
    private let onLines: @Sendable ([String]) -> Void

    private let lock = NSLock()
    private var isBusy = false
    private var isStopped = false
    private var lastRun = Date.distantPast

    /// Accurate recognition of a full panel takes a good fraction of a second,
    /// so frames are sampled rather than queued — the camera keeps up and the
    /// preview stays smooth.
    private static let minimumInterval: TimeInterval = 0.4

    init(orientation: CGImagePropertyOrientation, onLines: @escaping @Sendable ([String]) -> Void) {
        self.orientation = orientation
        self.onLines = onLines
    }

    func stop() {
        lock.lock()
        isStopped = true
        lock.unlock()
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        lock.lock()
        let shouldSkip = isBusy || isStopped || Date().timeIntervalSince(lastRun) < Self.minimumInterval
        if !shouldSkip {
            isBusy = true
            lastRun = Date()
        }
        lock.unlock()
        guard !shouldSkip else { return }

        defer {
            lock.lock()
            isBusy = false
            lock.unlock()
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // A nutrition panel is numbers and units. Language correction "fixes"
        // those into words and is actively harmful here.
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.01

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return
        }

        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { return }
        onLines(lines)
    }
}
