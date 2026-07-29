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
    @State private var showCustomRPCLockedSheet = false
    @State private var isLoading = false
    private let tierService = VultTierService()

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                        view(for: row)
                            .commonListItemContainer(index: index, itemsCount: rows.count)
                    }
                }
                .commonListContainer()
            }
        }
        .screenTitle("advanced".localized)
        .withLoading(isLoading: $isLoading)
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

    /// The rows this screen can show, composed as an ordered array so each row
    /// knows its position — that is what drives the shared list container's
    /// separators and end-row corner rounding.
    enum Row {
        case reshareVault
        case dilithiumKeygen
        case customMessage
        case onChainSecurity
        case customRPC
    }

    var rows: [Row] {
        var rows: [Row] = []
        if !vault.isFastVault && vault.publicKeyMLDSA44 == nil {
            rows.append(.reshareVault)
        }
        // Generating an MLDSA-44 post-quantum key is a one-time action, so hide
        // the row entirely once the vault already has one rather than surfacing
        // an entry point that dead-ends at an "already generated" notice.
        if vault.publicKeyMLDSA44 == nil {
            rows.append(.dilithiumKeygen)
        }
        rows.append(contentsOf: [.customMessage, .onChainSecurity, .customRPC])
        return rows
    }

    @ViewBuilder
    func view(for row: Row) -> some View {
        switch row {
        case .reshareVault:
            reshareVaultRow
        case .dilithiumKeygen:
            dilithiumKeygenRow
        case .customMessage:
            customMessageRow
        case .onChainSecurity:
            onChainSecurityRow
        case .customRPC:
            customRPCRow
        }
    }

    var reshareVaultRow: some View {
        Button {
            router.navigate(to: VaultRoute.reshare(vault: vault))
        } label: {
            SettingsCommonOptionView(icon: .upload4, title: "reshare".localized, subtitle: "reshareVault".localized)
        }
    }

    var dilithiumKeygenRow: some View {
        Button {
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
        } label: {
            SettingsCommonOptionView(
                icon: .atomShield,
                title: "dilithiumKeygen".localized,
                subtitle: "dilithiumKeygenSubtitle".localized
            )
        }
    }

    var customMessageRow: some View {
        Button {
            router.navigate(to: VaultRoute.customMessage(vault: vault))
        } label: {
            SettingsCommonOptionView(icon: .filePen, title: "sign".localized, subtitle: "signCustomMessage".localized)
        }
    }

    var onChainSecurityRow: some View {
        Button {
            router.navigate(to: VaultRoute.onChainSecurity)
        } label: {
            SettingsCommonOptionView(
                icon: .folderLock,
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
                icon: .mobileSignal,
                title: "settingsAdvancedCustomRPC",
                subtitle: "customRPCSubtitle".localized,
                titleAccessory: { VultTierBadge() },
                trailingView: {
                    Icon(.chevronRight, color: Theme.colors.textTertiary, size: 16)
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
