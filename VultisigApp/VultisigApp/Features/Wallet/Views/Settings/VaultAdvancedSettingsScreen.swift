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
    @State private var routingState: FastVaultRoutingState = .idle
    @State private var showCustomRPCLockedSheet = false
    @State private var isLoading = false
    private let tierService = VultTierService()

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                        view(for: row)
                            .commonListItemContainer(index: index, itemsCount: rows.count, style: .flush)
                    }
                }
                .commonListContainer(style: .flush)
            }
        }
        .task {
            if vault.publicKeyMLDSA44 == nil { _ = await FastVaultEligibilityRefresher.shared.presenceForRouting(vault) }
        }
        .task(id: routingState) {
            guard routingState == .checking else { return }
            let presence = await FastVaultEligibilityRefresher.shared.presenceForRouting(vault)
            guard !Task.isCancelled, routingState == .checking else { return }
            handlePresence(presence)
        }
        .onDisappear { routingState = .idle }
        .screenTitle("advanced".localized)
        .withLoading(isLoading: $isLoading)
        .crossPlatformSheet(isPresented: $showCustomRPCLockedSheet) {
            LockedFeatureSheet(
                feature: .customRPC,
                vault: vault,
                isPresented: $showCustomRPCLockedSheet,
                appearance: .settings
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
        // Generating an MLDSA-65 post-quantum key is a one-time action, so hide
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
            SettingsCommonOptionView(
                icon: .shareUpRight2,
                title: "reshare".localized,
                subtitle: "reshareVault".localized,
                titleStyle: .subtitle
            )
        }
    }

    var dilithiumKeygenRow: some View {
        VStack(spacing: 16) {
            Button(action: startKeygen) {
                SettingsCommonOptionView(
                    icon: .filePen,
                    title: "dilithiumKeygen".localized,
                    subtitle: "dilithiumKeygenSubtitle".localized,
                    titleStyle: .subtitle
                )
            }
            .disabled(routingState != .idle)
            FastVaultRoutingFeedback(
                state: routingState,
                onRetry: startKeygen,
                onPaired: {
                    routingState = .idle
                    navigateKeygen(useServer: false)
                }
            )
        }
    }

    private func startKeygen() {
        if let presence = FastVaultEligibilityRefresher.shared.confirmedPresenceForRouting(vault) {
            handlePresence(presence)
        } else {
            routingState = .checking
        }
    }

    private func handlePresence(_ presence: FastVaultPresence) {
        switch presence {
        case .present, .absent:
            routingState = .idle
            navigateKeygen(useServer: presence == .present)
        case .unknown:
            routingState = .failed
        }
    }

    private func navigateKeygen(useServer: Bool) {
        if useServer {
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

    var customMessageRow: some View {
        Button {
            router.navigate(to: VaultRoute.customMessage(vault: vault))
        } label: {
            SettingsCommonOptionView(
                icon: .penWriting,
                title: "sign".localized,
                subtitle: "signCustomMessage".localized,
                titleStyle: .subtitle
            )
        }
    }

    var onChainSecurityRow: some View {
        Button {
            router.navigate(to: VaultRoute.onChainSecurity)
        } label: {
            SettingsCommonOptionView(
                icon: .fileLock,
                title: "vaultSettingsSecurityTitle".localized,
                subtitle: "vaultSettingsSecuritySubtitle".localized,
                titleStyle: .subtitle
            )
        }
    }

    var customRPCRow: some View {
        Button {
            handleCustomRPCTap()
        } label: {
            SettingsOptionView(
                icon: .signature,
                title: "settingsAdvancedCustomRPC",
                subtitle: "customRPCSubtitle".localized,
                titleStyle: .subtitle,
                titleAccessory: { VultTierBadge() },
                trailingView: { SettingsChevronIcon() }
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
