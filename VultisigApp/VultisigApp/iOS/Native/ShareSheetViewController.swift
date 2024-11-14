//
//  ShareSheetViewController.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-07.
//
#if os(iOS)
import SwiftUI
    struct ShareSheetViewController: UIViewControllerRepresentable {
        var activityItems: [Any]
        var completion: ((Bool) -> Void)?
        var applicationActivities: [UIActivity]? = nil

        func makeUIViewController(context: UIViewControllerRepresentableContext<ShareSheetViewController>) -> UIActivityViewController {
            let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
            controller.completionWithItemsHandler = { activityType, completed, returnedItems, error in
                if completed {
                    completion?(true)
                } else {
                    completion?(false)
                }
            }
            return controller
        }

        func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ShareSheetViewController>) {}
    }
#endif
