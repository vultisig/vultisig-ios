//
//  QRCodeShareSheet.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

#if os(iOS)
import UIKit
import SwiftUI

struct QRCodeShareSheet: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    // swiftlint:disable:next unused_parameter
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }
    // swiftlint:disable:next unused_parameter
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No update needed
    }
}
#endif
