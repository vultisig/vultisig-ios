import SwiftUI

/// Hosted ceremonies require an action-time check. Unknown never selects a
/// ceremony; the user can retry or explicitly choose their paired devices.
struct FastVaultPresenceGate: View {
    let vault: Vault
    let onResolved: (Bool) -> Void
    var resolve: @MainActor (Vault) async -> FastVaultPresence = {
        await FastVaultEligibilityRefresher.shared.resolvePresence($0)
    }
    @State private var isChecking = true
    @State private var attempt = 0

    var body: some View {
        Screen {
            VStack(spacing: 24) {
                if isChecking {
                    ProgressView()
                } else {
                    Text("errorNetworkUnstableTitle".localized)
                        .font(Theme.fonts.title2)
                    Text("errorNetworkUnstableDescription".localized)
                        .font(Theme.fonts.bodyMRegular)
                    PrimaryButton(title: "tryAgain".localized) {
                        isChecking = true
                        attempt += 1
                    }
                    PrimaryButton(title: "paired".localized, type: .secondary) {
                        onResolved(false)
                    }
                }
            }
            .foregroundStyle(Theme.colors.textPrimary)
        }
        .task(id: attempt) {
            guard vault.hasServerSigner else {
                onResolved(false)
                return
            }
            let outcome = await resolve(vault)
            guard !Task.isCancelled else { return }
            switch outcome {
            case .present: onResolved(true)
            case .absent: onResolved(false)
            case .unknown: isChecking = false
            }
        }
    }
}

struct UpgradeVaultRoutingScreen: View {
    let vault: Vault
    @State private var useServer: Bool?

    var body: some View {
        if let useServer {
            if useServer {
                VaultShareBackupsView(vault: vault, useServer: true)
            } else {
                AllDevicesUpgradeView(vault: vault)
            }
        } else {
            FastVaultPresenceGate(vault: vault) { useServer = $0 }
        }
    }
}
