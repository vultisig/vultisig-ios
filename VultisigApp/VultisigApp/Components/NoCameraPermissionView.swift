//
//  NoCameraPermissionView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-30.
//

import SwiftUI

struct NoCameraPermissionView: View {
    var body: some View {
        ErrorView(
            type: .warning,
            title: "noCameraPermissionError".localized,
            description: "",
            buttonTitle: "openSettings".localized,
            action: openSettings
        )
    }
}

#Preview {
    NoCameraPermissionView()
}

#if os(iOS)
import SwiftUI

extension NoCameraPermissionView {
    func openSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
}
#endif

#if os(macOS)
import Cocoa
import SwiftUI

extension NoCameraPermissionView {
    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
