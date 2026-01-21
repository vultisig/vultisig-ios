//
//  MacCameraPreview.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-15.
//
#if os(macOS)
import SwiftUI
import AVFoundation

struct MacCameraPreview: NSViewRepresentable {
    var session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer = previewLayer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer as? AVCaptureVideoPreviewLayer {
            layer.session = session
        }
    }
}

#Preview {
    MacCameraPreview(session: AVCaptureSession())
}
#endif
