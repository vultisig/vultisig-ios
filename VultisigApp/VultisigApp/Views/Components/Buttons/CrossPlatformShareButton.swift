//
//  CrossPlatformShareButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/08/2025.
//

import SwiftUI

public struct CrossPlatformShareButton<Content: View>: View {
    private let image: Image
    private let caption: String
    private let scale: CGFloat
    private let content: (@escaping () -> Void) -> Content

    public init(
        image: Image,
        caption: String,
        scale: CGFloat = 2,
        @ViewBuilder content: @escaping (@escaping () -> Void) -> Content
    ) {
        self.image = image
        self.caption = caption
        self.scale = scale
        self.content = content
    }

    public var body: some View {
        #if os(iOS)
        IOSShareButton(image: image, caption: caption, scale: scale, content: content)
        #elseif os(macOS)
        MacShareButton(image: image, caption: caption, scale: scale, content: content)
        #endif
    }
}

@MainActor
private func renderPNGData(from image: Image, scale: CGFloat) -> Data? {
    let renderer = ImageRenderer(content: image)
    renderer.scale = scale
    #if os(iOS)
    return renderer.uiImage?.pngData()
    #elseif os(macOS)
    guard
        let nsImage = renderer.nsImage,
        let tiff = nsImage.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff)
    else { return nil }
    return rep.representation(using: .png, properties: [:])
    #endif
}

#if os(iOS)
import UIKit

private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct IOSShareButton<Content: View>: View {
    let image: Image
    let caption: String
    let scale: CGFloat
    let content: (@escaping () -> Void) -> Content

    @State private var cachedImage: UIImage?
    @State private var payload: SharePayload?

    var body: some View {
        content(share)
            .task {
                if cachedImage == nil,
                   let png = renderPNGData(from: image, scale: scale),
                   let ui = UIImage(data: png) {
                    cachedImage = ui
                }
            }
            .sheet(item: $payload) { payload in
                ActivityViewController(items: payload.items)
                    .ignoresSafeArea()
            }
    }

    private func share() {
        var items: [Any] = [caption]
        if let ui = cachedImage {
            items.insert(ui, at: 0)
        } else if let png = renderPNGData(from: image, scale: scale),
                  let ui = UIImage(data: png) {
            items.insert(ui, at: 0)
            cachedImage = ui
        }

        payload = SharePayload(items: items)
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]
    // swiftlint:disable:next unused_parameter
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            vc.popoverPresentationController?.sourceView = window.rootViewController?.view
        }
        return vc
    }
    // swiftlint:disable:next unused_parameter
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif

#if os(macOS)
import AppKit

private struct MacShareButton<Content: View>: View {
    let image: Image
    let caption: String
    let scale: CGFloat
    let content: (@escaping () -> Void) -> Content

    @State private var cachedImage: NSImage?
    @State private var showSharePicker = false
    @State private var buttonFrame: CGRect = .zero

    var body: some View {
        content(share)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: FramePreferenceKey.self, value: geometry.frame(in: .global))
                }
            )
            .onPreferenceChange(FramePreferenceKey.self) { frame in
                buttonFrame = frame
            }
            .task {
                if cachedImage == nil,
                   let png = renderPNGData(from: image, scale: scale) {
                    cachedImage = NSImage(data: png)
                }
            }
            .background(
                // Invisible view to handle the share picker
                SharePickerView(
                    items: shareItems,
                    isPresented: $showSharePicker,
                    sourceRect: buttonFrame
                )
            )
    }

    private var shareItems: [Any] {
        var items: [Any] = [caption]
        if let cachedImage = cachedImage {
            items.insert(cachedImage, at: 0)
        } else if let png = renderPNGData(from: image, scale: scale),
                  let nsImage = NSImage(data: png) {
            items.insert(nsImage, at: 0)
        }
        return items
    }

    private func share() {
        showSharePicker = true
    }
}

// Helper view to manage the macOS share picker
private struct SharePickerView: NSViewRepresentable {
    let items: [Any]
    @Binding var isPresented: Bool
    let sourceRect: CGRect

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.parentView = view
        return view
    }
    // swiftlint:disable:next unused_parameter
    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            context.coordinator.showSharePicker(items: items, sourceRect: sourceRect)
            DispatchQueue.main.async {
                isPresented = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject {
        weak var parentView: NSView?

        func showSharePicker(items: [Any], sourceRect: CGRect) {
            guard let parentView = parentView,
                  let window = parentView.window else { return }

            let picker = NSSharingServicePicker(items: items)

            // Convert the global frame to the window's coordinate system
            let windowRect = window.convertFromScreen(sourceRect)
            let viewRect = parentView.convert(windowRect, from: nil)

            picker.show(relativeTo: viewRect, of: parentView, preferredEdge: .minY)
        }
    }
}

// Helper preference key for getting the button's frame
private struct FramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}
#endif
