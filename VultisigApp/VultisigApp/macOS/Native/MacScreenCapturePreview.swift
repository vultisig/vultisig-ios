//
//  MacScreenCapturePreview.swift
//  VultisigApp
//

#if os(macOS)
import SwiftUI
import AppKit

/// Makes the window transparent so the screen content behind is visible,
/// and reports its screen position to the scan region for QR detection cropping.
struct MacScreenCapturePreview: NSViewRepresentable {
    var scanRegion: ScanRegion

    func makeNSView(context: Context) -> ScreenTransparentNSView {
        let view = ScreenTransparentNSView()
        view.scanRegion = scanRegion
        return view
    }

    // swiftlint:disable:next unused_parameter
    func updateNSView(_ nsView: ScreenTransparentNSView, context: Context) {
        nsView.updateScanRegion()
    }
}

class ScreenTransparentNSView: NSView {
    var scanRegion: ScanRegion?
    private var moveObserver: NSObjectProtocol?
    private var resizeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let window = window {
            window.isOpaque = false
            window.backgroundColor = .clear
            setupObservers()
            updateScanRegion()
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        // Restore opacity on the old window before leaving
        if newWindow == nil, let oldWindow = window {
            oldWindow.isOpaque = true
            oldWindow.backgroundColor = NSColor.windowBackgroundColor
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func updateScanRegion() {
        guard let window = window,
              let screen = window.screen ?? NSScreen.main else {
            return
        }

        let viewFrameInWindow = convert(bounds, to: nil)
        let viewFrameOnScreen = window.convertToScreen(viewFrameInWindow)
        let screenFrame = screen.frame

        // Normalized rect in screen coordinates (bottom-left origin, matching CIImage)
        let normX = (viewFrameOnScreen.origin.x - screenFrame.origin.x) / screenFrame.width
        let normY = (viewFrameOnScreen.origin.y - screenFrame.origin.y) / screenFrame.height
        let normW = viewFrameOnScreen.width / screenFrame.width
        let normH = viewFrameOnScreen.height / screenFrame.height

        scanRegion?.normalizedRect = CGRect(x: normX, y: normY, width: normW, height: normH)
    }

    private func setupObservers() {
        removeObservers()

        guard let window = window else { return }

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.updateScanRegion()
        }

        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.updateScanRegion()
        }
    }

    private func removeObservers() {
        if let observer = moveObserver {
            NotificationCenter.default.removeObserver(observer)
            moveObserver = nil
        }
        if let observer = resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            resizeObserver = nil
        }
    }

    deinit {
        removeObservers()
    }
}
#endif
