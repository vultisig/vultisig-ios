//
//  VaultShareBackupsView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-11.
//

import SwiftUI

struct VaultShareBackupsView: View {
    let vault: Vault
    var resolveHostedRouting = false
    @State private var routingState: FastVaultRoutingState = .idle

    @Environment(\.router) var router

    var body: some View {
        ZStack {
            Background()
            content
        }
        .task {
            if resolveHostedRouting { _ = await FastVaultEligibilityRefresher.shared.presenceForRouting(vault) }
        }
        .task(id: routingState) {
            guard routingState == .checking else { return }
            let presence = await FastVaultEligibilityRefresher.shared.presenceForRouting(vault)
            guard !Task.isCancelled, routingState == .checking else { return }
            handlePresence(presence)
        }
        .onDisappear { routingState = .idle }
    }

    var image: some View {
        Image("VaultShareBackupsImage")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 512, maxHeight: 512)
            .scaleEffect(1.1)
            .padding(-36)
    }

    var description: some View {
        Group {
            Text(NSLocalizedString("vaultShareBackupsViewTitle1", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString("vaultShareBackupsViewTitle2", comment: ""))
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .multilineTextAlignment(.center)
        .font(Theme.fonts.title1)
    }

    var button: some View {
        VStack(spacing: 16) {
            if routingState == .idle {
                PrimaryButton(title: "next", action: continueUpgrade)
                    .frame(width: resolveHostedRouting ? nil : 120)
            }
            FastVaultRoutingFeedback(
                state: routingState,
                onRetry: continueUpgrade,
                onPaired: choosePairedUpgrade
            )
        }
        .padding(.vertical, 36)
    }

    private func continueUpgrade() {
        guard resolveHostedRouting else {
            navigatePaired()
            return
        }
        if let presence = FastVaultEligibilityRefresher.shared.confirmedPresenceForRouting(vault) {
            handlePresence(presence)
        } else {
            routingState = .checking
        }
    }

    private func handlePresence(_ presence: FastVaultPresence) {
        switch presence {
        case .present:
            routingState = .idle
            navigateHosted()
        case .absent:
            choosePairedUpgrade()
        case .unknown:
            routingState = .failed
        }
    }

    private func choosePairedUpgrade() {
        routingState = .idle
        router.navigate(to: VaultRoute.allDevicesUpgrade(vault: vault, hasReviewedBackups: true))
    }

    private func navigatePaired() {
        router.navigate(to: KeygenRoute.peerDiscovery(
            tssType: .Migrate,
            vault: vault,
            selectedTab: .secure,
            fastSignConfig: nil,
            keyImportInput: nil,
            setupType: nil,
            singleKeygenType: nil
        ))
    }

    private func navigateHosted() {
        router.navigate(to: KeygenRoute.fastVaultPassword(
            tssType: .Migrate,
            vault: vault,
            selectedTab: vault.signers.count == 2 ? .fast : .active,
            isExistingVault: true,
            singleKeygenType: nil
        ))
    }

}

#Preview {
    VaultShareBackupsView(vault: Vault.example)
}

#if os(iOS)
extension VaultShareBackupsView {
    var content: some View {
        ZStack {
            VStack {
                image
                Spacer()
            }

            VStack(spacing: 0) {
                Spacer()
                description
                button
            }
        }
        .padding(36)
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
    }
}
#endif

#if os(macOS)
extension VaultShareBackupsView {
    var content: some View {
        VStack(spacing: 0) {
            Spacer()
            image
            Spacer()
            description
            button
        }
        .padding(.bottom, 36)
        .crossPlatformToolbar()
    }
}
#endif
