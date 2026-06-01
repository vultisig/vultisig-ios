//
//  MacScreenCaptureService.swift
//  VultisigApp
//

#if os(macOS)
import ScreenCaptureKit
import CoreImage
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "screen-capture")

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
    @Published var isPermissionDenied = false

    let scanRegion = ScanRegion()

    private var stream: SCStream?
    private var streamOutput: ScreenCaptureStreamOutput?

    func startCapture() async {
        guard stream == nil else {
            logger.debug("startCapture skipped — stream already running")
            return
        }

        detectedQRCode = nil
        isPermissionDenied = false

        do {
            logger.info("Starting screen capture")
            let content = try await SCShareableContent.current

            let mainDisplayID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == mainDisplayID }) ?? content.displays.first else {
                logger.error("No shareable display found (displays: \(content.displays.count))")
                return
            }

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
            logger.info("Screen capture started (display \(display.width)x\(display.height), excluded windows: \(excludedWindows.count))")
        } catch let error as SCStreamError where error.code == .userDeclined {
            logger.warning("Screen recording permission denied")
            isPermissionDenied = true
        } catch {
            logger.error("Screen capture failed to start: \(error.localizedDescription)")
        }
    }

    func stopCapture() {
        guard let stream = stream else { return }

        Task {
            try? await stream.stopCapture()
        }
        self.stream = nil
        self.streamOutput = nil
    }
}

private class ScreenCaptureStreamOutput: NSObject, SCStreamOutput {
    private let scanRegion: ScanRegion
    private let onQRCodeDetected: (String) -> Void
    private let ciContext = CIContext()
    private let qrDetector: CIDetector?
    private var loggedFirstFrame = false

    init(
        scanRegion: ScanRegion,
        onQRCodeDetected: @escaping (String) -> Void
    ) {
        self.scanRegion = scanRegion
        self.onQRCodeDetected = onQRCodeDetected
        self.qrDetector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: ciContext,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
        super.init()
    }

    func stream(
        _: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let region = scanRegion.normalizedRect
        let extent = ciImage.extent

        if !loggedFirstFrame {
            loggedFirstFrame = true
            logger.info("First capture frame \(Int(extent.width))x\(Int(extent.height)), scanRegion=\(region.debugDescription)")
        }

        let imageToScan: CIImage
        if region.isEmpty {
            // Scan full frame when scan region is not yet set
            imageToScan = ciImage
        } else {
            let cropRect = CGRect(
                x: region.origin.x * extent.width,
                y: region.origin.y * extent.height,
                width: region.size.width * extent.width,
                height: region.size.height * extent.height
            ).intersection(extent)

            guard !cropRect.isEmpty else {
                logger.debug("Crop rect empty for region \(region.debugDescription) — skipping frame")
                return
            }
            // CIDetector is unreliable on images whose extent has a non-zero
            // origin, so translate the cropped region back to (0, 0) before
            // running QR detection.
            imageToScan = ciImage
                .cropped(to: cropRect)
                .transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y))
        }

        guard let features = qrDetector?.features(in: imageToScan) as? [CIQRCodeFeature] else { return }

        for feature in features {
            if let qrString = feature.messageString, !qrString.isEmpty {
                logger.info("QR code detected in screen capture")
                onQRCodeDetected(qrString)
                return
            }
        }
    }
}
#endif
