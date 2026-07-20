//
//  QuantumSecurityIntroScreen.swift
//  VultisigApp
//
//  Pre-keygen intro for the QBTC quantum-security flow. Shown when
//  the user wants to use QBTC but the vault doesn't yet have an
//  ML-DSA-44 key pair (W2 token selection + W3 BTC claim banner).
//  "Get started" forwards to the existing keygen route for the
//  vault type — `KeygenRoute.fastVaultPassword(...singleKeygenType:
//  .MLDSA)` for FastVault, `KeygenRoute.peerDiscovery(...)` for
//  SecureVault — and the actual completion handoff happens via
//  `Notification.Name.qbtcQuantumKeygenCompleted` (see
//  `QuantumKeygenNotification`).
//

import RiveRuntime
import SwiftUI

struct QuantumSecurityIntroScreen: View {
    let vault: Vault

    @Environment(\.router) private var router
    @State private var animationVM: RiveViewModel?

    init(vault: Vault) {
        self.vault = vault
    }

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 32) {
                        header
                        animation
                        featureList
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }

                PrimaryButton(title: "quantumSecurityIntroCta".localized) {
                    onGetStarted()
                }
            }
        }
        .onAppear {
            guard animationVM == nil else { return }
            animationVM = RiveViewModel(fileName: "quantum_key_pair", autoPlay: true)
            animationVM?.fit = .fitHeight
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("quantumSecurityIntroTitle".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
            Text("quantumSecurityIntroDescription".localized)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var animation: some View {
        animationVM?.view()
            .frame(height: 240)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuantumSecurityFeatureRow(
                icon: .folderKey,
                title: "quantumSecurityFeatureGenerateTitle".localized,
                subtitle: "quantumSecurityFeatureGenerateSubtitle".localized
            )
            QuantumSecurityFeatureRow(
                icon: .keyboard3,
                title: "quantumSecurityFeatureLinkTitle".localized,
                subtitle: "quantumSecurityFeatureLinkSubtitle".localized
            )
            QuantumSecurityFeatureRow(
                icon: .coins,
                title: "quantumSecurityFeatureClaimTitle".localized,
                subtitle: "quantumSecurityFeatureClaimSubtitle".localized
            )
        }
    }

    // MARK: - Actions

    private func onGetStarted() {
        // Matches the existing branch in `VaultAdvancedSettingsScreen`'s
        // `dilithiumKeygenRow`: FastVault uses the password screen,
        // SecureVault goes through peer discovery. The MLDSA pubkey
        // lands on the vault inside `KeygenViewModel.startMldsaKeygen`,
        // which is also where the completion notification fires.
        if vault.isFastVault {
            router.navigate(
                to: KeygenRoute.fastVaultPassword(
                    tssType: .SingleKeygen,
                    vault: vault,
                    selectedTab: .fast,
                    isExistingVault: true,
                    singleKeygenType: .MLDSA
                )
            )
        } else {
            router.navigate(
                to: KeygenRoute.peerDiscovery(
                    tssType: .SingleKeygen,
                    vault: vault,
                    selectedTab: .secure,
                    fastSignConfig: nil,
                    keyImportInput: nil,
                    setupType: nil,
                    singleKeygenType: .MLDSA
                )
            )
        }
    }
}

#Preview {
    QuantumSecurityIntroScreen(vault: .example)
}
