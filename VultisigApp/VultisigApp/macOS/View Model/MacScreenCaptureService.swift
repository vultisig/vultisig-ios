//
//  MacScreenCaptureService.swift
//  VultisigApp
//

#if os(macOS)
import ScreenCaptureKit
import CoreImage
import SwiftUI

enum ScreenCapturePermissionState {
    case unknown
    case granted
    case denied
}

/// Thread-safe normalized rect (0..1) in screen coordinates (bottom-left origin).
/// Written by the preview NSView, read by the stream output for cropping QR detection.
final class ScanRegion: @unchecked Sendable {
    private var rect = CGRect.zero
    private let lock = NSLock()

    var normalizedRect: CGRect {
        get { lock.lock(); defer { lock.unlock() }; return rect }
        set { lock.lock(); defer { lock.unlock() }; rect = newValue }
    }
}

@MainActor
class MacScreenCaptureService: ObservableObject {
    @Published var detectedQRCode: String?
    @Published var permissionState: ScreenCapturePermissionState = .unknown
    @Published var isCapturing = false

    let scanRegion = ScanRegion()

    private var stream: SCStream?
    private var streamOutput: ScreenCaptureStreamOutput?

    func startCapture() async {
        detectedQRCode = nil

        do {
            let content = try await SCShareableContent.current
            permissionState = .granted

            guard let display = content.displays.first else { return }

            let excludedWindows = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            }

            let filter = SCContentFilter(
                display: display,
                excludingWindows: excludedWindows
            )

            let config = SCStreamConfiguration()
            let displayAspect = CGFloat(display.width) / CGFloat(display.height)
            config.width = 1920
            config.height = Int(1920.0 / displayAspect)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 2)
            config.showsCursor = false

            let output = ScreenCaptureStreamOutput(
                scanRegion: scanRegion,
                onQRCodeDetected: { [weak self] qrCode in
                    Task { @MainActor in
                        self?.detectedQRCode = qrCode
                    }
                }
            )
            streamOutput = output

            let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
            try newStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
            try await newStream.startCapture()

            stream = newStream
            isCapturing = true
        } catch {
            if (error as NSError).domain == "com.apple.ScreenCaptureKit" {
                permissionState = .denied
            }
        }
    }

    func stopCapture() {
        guard let stream = stream else { return }

        Task {
            try? await stream.stopCapture()
        }
        self.stream = nil
        self.streamOutput = nil
        isCapturing = false
    }
}

private class ScreenCaptureStreamOutput: NSObject, SCStreamOutput {
    private let scanRegion: ScanRegion
    private let onQRCodeDetected: (String) -> Void
    private let ciContext = CIContext()
    private var lastDetectionTime: Date = .distantPast
    private let detectionInterval: TimeInterval = 0.5

    init(
        scanRegion: ScanRegion,
        onQRCodeDetected: @escaping (String) -> Void
    ) {
        self.scanRegion = scanRegion
        self.onQRCodeDetected = onQRCodeDetected
        super.init()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }

        let now = Date()
        guard now.timeIntervalSince(lastDetectionTime) >= detectionInterval else { return }
        lastDetectionTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Crop to the visible preview region before QR detection
        let region = scanRegion.normalizedRect
        guard !region.isEmpty else { return }

        let extent = ciImage.extent
        let cropRect = CGRect(
            x: region.origin.x * extent.width,
            y: region.origin.y * extent.height,
            width: region.size.width * extent.width,
            height: region.size.height * extent.height
        ).intersection(extent)

        guard !cropRect.isEmpty else { return }
        let croppedImage = ciImage.cropped(to: cropRect)
        detectQRCode(in: croppedImage)
    }

    private func detectQRCode(in image: CIImage) {
        let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: ciContext,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )

        guard let features = detector?.features(in: image) as? [CIQRCodeFeature] else { return }

        for feature in features {
            if let qrString = feature.messageString, !qrString.isEmpty {
                onQRCodeDetected(qrString)
                return
            }
        }
    }
}
#endif
