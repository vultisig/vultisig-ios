//
//  NoLocalNetworkPermissionView.swift
//  VultisigApp
//

import SwiftUI

/// Shown when local (LAN / Bonjour) peer discovery can't reach the other device
/// — most often because iOS **Local Network** access is off for Vultisig, or the
/// two devices aren't on the same Wi-Fi. Offers a deep link to Settings (where
/// the Local Network toggle lives) plus a Retry that re-runs discovery.
struct NoLocalNetworkPermissionView: View {
    var onRetry: () -> Void

    var body: some View {
        ErrorView(
            type: .warning,
            title: "noLocalNetworkPermissionTitle".localized,
            description: "noLocalNetworkPermissionDescription".localized,
            buttonTitle: "openSettings".localized,
            secondaryButtonTitle: "tryAgain".localized,
            action: openSettings,
            secondaryAction: onRetry
        )
    }
}

#Preview {
    NoLocalNetworkPermissionView(onRetry: {})
}

#if os(iOS)
extension NoLocalNetworkPermissionView {
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
#endif

#if os(macOS)
import Cocoa

extension NoLocalNetworkPermissionView {
    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }
}
#endif
