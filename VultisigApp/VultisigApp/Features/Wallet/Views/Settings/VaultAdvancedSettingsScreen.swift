//
//  VaultAdvancedSettingsScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 20/08/2025.
//

import SwiftUI
import SwiftData

struct VaultAdvancedSettingsScreen: View {
    @ObservedObject var vault: Vault

    @Environment(\.router) var router
    @State private var showDilithiumAlreadyGenerated = false
    @State private var showCustomRPCLockedSheet = false
    @State private var isLoading = false
    private let tierService = VultTierService()

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                SettingsSectionContainerView {
                    VStack(spacing: 0) {
                        reshareVaultRow
                        dilithiumKeygenRow
                        customMessageRow
                        onChainSecurityRow
                        customRPCRow
                    }
                }
            }
        }
        .screenTitle("advanced".localized)
        .withLoading(isLoading: $isLoading)
        .crossPlatformSheet(isPresented: $showDilithiumAlreadyGenerated) {
            DilithiumAlreadyGeneratedSheet(isPresented: $showDilithiumAlreadyGenerated)
        }
        .crossPlatformSheet(isPresented: $showCustomRPCLockedSheet) {
            LockedFeatureSheet(
                feature: .customRPC,
                vault: vault,
                isPresented: $showCustomRPCLockedSheet
            ) {
                showCustomRPCLockedSheet = false
                router.navigate(to: VaultRoute.swap(
                    fromCoin: vault.nativeCoin(for: .ethereum),
                    toCoin: tierService.getVultToken(for: vault),
                    vault: vault
                ))
            }
        }
    }

    @ViewBuilder
    var reshareVaultRow: some View {
        if !vault.isFastVault && vault.publicKeyMLDSA44 == nil {
            Button {
                router.navigate(to: VaultRoute.reshare(vault: vault))
            } label: {
                SettingsCommonOptionView(icon: "share", title: "reshare".localized, subtitle: "reshareVault".localized)
            }
        }
    }

    var dilithiumKeygenRow: some View {
        Button {
            if vault.publicKeyMLDSA44 != nil {
                showDilithiumAlreadyGenerated = true
            } else if vault.isFastVault {
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
        } label: {
            SettingsCommonOptionView(
                icon: "atom-shield",
                title: "dilithiumKeygen".localized,
                subtitle: "dilithiumKeygenSubtitle".localized
            )
        }
    }

    var customMessageRow: some View {
        Button {
            router.navigate(to: VaultRoute.customMessage(vault: vault))
        } label: {
            SettingsCommonOptionView(icon: "file-pen-line", title: "sign".localized, subtitle: "signCustomMessage".localized)
        }
    }

    var onChainSecurityRow: some View {
        Button {
            router.navigate(to: VaultRoute.onChainSecurity)
        } label: {
            SettingsCommonOptionView(
                icon: "folder-lock",
                title: "vaultSettingsSecurityTitle".localized,
                subtitle: "vaultSettingsSecuritySubtitle".localized
            )
        }
    }

    var customRPCRow: some View {
        Button {
            handleCustomRPCTap()
        } label: {
            SettingsOptionView(
                icon: "signal-tower",
                title: "settingsAdvancedCustomRPC",
                subtitle: "customRPCSubtitle".localized,
                showSeparator: false,
                titleAccessory: { VultTierBadge() },
                trailingView: {
                    Icon(named: "chevron-right", color: Theme.colors.textTertiary, size: 16)
                }
            )
        }
    }

    private func handleCustomRPCTap() {
        Task {
            isLoading = true
            defer { isLoading = false }
            await TierGatedTap.handle(
                required: .silver,
                show: lockedSheetBinding,
                for: vault,
                isUnlocked: { tier, vault in
                    guard let cached = await tierService.fetchDiscountTier(for: vault, cached: true) else {
                        return false
                    }
                    return cached >= tier
                },
                onUnlocked: {
                    router.navigate(to: VaultRoute.customRPC(vault: vault))
                }
            )
        }
    }

    /// Bridges the boolean sheet flag to the `VultDiscountTier?` binding
    /// `TierGatedTap` expects: any non-nil tier means "locked", which we surface
    /// as the single `LockedFeatureSheet(.customRPC)`.
    private var lockedSheetBinding: Binding<VultDiscountTier?> {
        Binding(
            get: { showCustomRPCLockedSheet ? .silver : nil },
            set: { showCustomRPCLockedSheet = $0 != nil }
        )
    }
}
