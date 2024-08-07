//
//  ShareSheetViewController.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-07.
//

import SwiftUI

#if os(iOS)
    struct ShareSheetViewController: UIViewControllerRepresentable {
        var activityItems: [Any]
        var applicationActivities: [UIActivity]? = nil

        func makeUIViewController(context: UIViewControllerRepresentableContext<ShareSheetViewController>) -> UIActivityViewController {
            let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
            return controller
        }

        func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ShareSheetViewController>) {}
    }
#elseif os(macOS)
struct ShareSheetViewController: NSViewRepresentable {
    var items: [Any]
    var onDismiss: () -> Void
    @Binding var alreadyShowingPopup: Bool
    
    class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var parent: ShareSheetViewController
        
        init(_ parent: ShareSheetViewController) {
            self.parent = parent
        }
        
        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            if service == nil {
                parent.onDismiss()
            }
        }
        
        func sharingServicePickerDidEnd(_ sharingServicePicker: NSSharingServicePicker) {
            parent.onDismiss()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard !alreadyShowingPopup else {
            return
        }
        
        DispatchQueue.main.async {
            alreadyShowingPopup = true
            
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = context.coordinator
            picker.show(relativeTo: .zero, of: nsView, preferredEdge: .minY)
        }
    }
}
#endif
