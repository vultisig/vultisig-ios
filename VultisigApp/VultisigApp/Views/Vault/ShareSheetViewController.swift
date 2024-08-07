//
//  ShareSheetViewController.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-07.
//

import SwiftUI

struct ShareSheetViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: UIViewControllerRepresentableContext<ShareSheetViewController>) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: UIViewControllerRepresentableContext<ShareSheetViewController>) {}
}
