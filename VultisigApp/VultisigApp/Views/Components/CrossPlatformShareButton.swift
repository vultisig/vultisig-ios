//
//  CrossPlatformShareButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/08/2025.
//

import SwiftUI

public struct CrossPlatformShareButton<Label: View>: View {
    private let image: Image
    private let caption: String
    private let scale: CGFloat
    private let label: () -> Label

    public init(
        image: Image,
        caption: String,
        scale: CGFloat = 2,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.image = image
        self.caption = caption
        self.scale = scale
        self.label = label
    }

    public var body: some View {
        #if os(iOS)
        IOSShareButton(image: image, caption: caption, scale: scale, label: { label() })
        #elseif os(macOS)
        MacShareButton(image: image, caption: caption, scale: scale, label: { label() })
        #endif
    }
}

@MainActor
private func renderPNGData(from image: Image, scale: CGFloat) -> Data? {
    let renderer = ImageRenderer(content: image) // no resizing
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

private struct IOSShareButton<Label: View>: View {
    let image: Image
    let caption: String
    let scale: CGFloat
    @ViewBuilder var label: () -> Label

    @State private var cachedImage: UIImage?
    @State private var payload: SharePayload?

    var body: some View {
        Button(action: share, label: label)
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
        // Build from cached pieces (fast), with a safe fallback
        var items: [Any] = [caption]
        if let ui = cachedImage {
            items.insert(ui, at: 0) // [image, text]
        } else if let png = renderPNGData(from: image, scale: scale),
                  let ui = UIImage(data: png) {
            items.insert(ui, at: 0)
            cachedImage = ui // cache for next time
        }

        UIPasteboard.general.string = caption
        payload = SharePayload(items: items)
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = UIApplication.shared
            .connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        return vc
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#endif


#if os(macOS)
import AppKit

private struct MacShareButton<Label: View>: NSViewRepresentable {
    let image: Image
    let caption: String
    let scale: CGFloat
    @ViewBuilder var label: () -> Label

    func makeNSView(context: Context) -> NSButton {
        let hosting = NSHostingView(rootView: AnyView(label()))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton()
        button.bezelStyle = .texturedRounded
        button.title = ""
        button.target = context.coordinator
        button.action = #selector(Coordinator.share)

        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])

        context.coordinator.button = button
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(image: image, caption: caption, scale: scale)
    }

    final class Coordinator: NSObject {
        let image: Image
        let caption: String
        let scale: CGFloat
        weak var button: NSButton?

        init(image: Image, caption: String, scale: CGFloat) {
            self.image = image
            self.caption = caption
            self.scale = scale
        }

        @MainActor @objc func share() {
            var items: [Any] = [caption]
            if let png = renderPNGData(from: image, scale: scale),
               let ns = NSImage(data: png) {
                items.insert(ns, at: 0)
            }

            let picker = NSSharingServicePicker(items: items)
            if let button = button {
                picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}
#endif
