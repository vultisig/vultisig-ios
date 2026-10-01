//
//  WalletConnectProposalApprovalSheet.swift
//  VultisigApp
//

import SwiftData
import SwiftUI

struct WalletConnectProposalApprovalSheet: View {
    let proposal: WalletConnectProposal
    let coordinator: WalletConnectCoordinator

    @Query(sort: \Vault.order) private var vaults: [Vault]
    @State private var selectedVaultPubKey = ""
    @State private var actionError: Error?
    @State private var isApproving = false
    @State private var isRejecting = false
    @State private var showAllNetworks = false
    @State private var showVaultSelection = false

    private var selectedVault: Vault? {
        vaults.first { $0.pubKeyECDSA == selectedVaultPubKey } ?? vaults.first
    }

    private var approvalError: Error? {
        guard let selectedVault else { return WalletConnectNamespaceApprovalError.noEVMAccounts }
        do {
            _ = try WalletConnectEVMNamespaceAdapter().buildApproval(
                requiredNamespaces: proposal.requiredNamespaces,
                optionalNamespaces: proposal.optionalNamespaces,
                accounts: selectedVault.walletConnectEVMAccounts
            )
            return nil
        } catch {
            return error
        }
    }

    private var canApprove: Bool {
        selectedVault != nil && approvalError == nil && !isApproving && !isRejecting
    }

    private var networks: [WalletConnectChainDisplay] {
        WalletConnectChainDisplay.unique(
            from: (proposal.requiredNamespaces + proposal.optionalNamespaces).flatMap(\.chains)
        )
    }

    private var visibleNetworks: [WalletConnectChainDisplay] {
        showAllNetworks ? networks : Array(networks.prefix(3))
    }

    var body: some View {
        VStack(spacing: 0) {
            WalletConnectSheetHeader(
                title: "walletConnectConnectionRequest".localized,
                onClose: isApproving || isRejecting ? nil : reject
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    WalletConnectCenteredDAppIdentity(
                        name: proposal.name,
                        host: proposal.displayHost,
                        iconURL: proposal.icons.first,
                        verifyContext: proposal.verifyContext
                    )
                    .padding(.top, 6)

                    WalletConnectVerifyContextView(verifyContext: proposal.verifyContext)

                    vaultSelector
                    networksCard
                    permissionsSection
                    approvalWarning
                    reminder
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            decisionFooter
        }
        .background(Color.walletConnectBackground.ignoresSafeArea())
        .onAppear {
            if selectedVaultPubKey.isEmpty {
                selectedVaultPubKey = vaults.first?.pubKeyECDSA ?? ""
            }
        }
        .withError(error: $actionError, errorType: .warning) {
            actionError = nil
        }
    }

    private var vaultSelector: some View {
        Button {
            showVaultSelection = true
        } label: {
            WalletConnectVaultCard(
                title: selectedVault?.name ?? "vault".localized,
                subtitle: selectedVault?.signerPartDescription ?? "-",
                style: selectedVault?.offersFastSigning == true ? .fast : .secure,
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .disabled(vaults.isEmpty || isApproving || isRejecting)
        .crossPlatformSheet(isPresented: $showVaultSelection) {
            vaultSelectionSheet
        }
    }

    private var vaultSelectionSheet: some View {
        VStack(spacing: 0) {
            vaultSelectionHeader
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

            List {
                ForEach(Array(vaults.enumerated()), id: \.element.pubKeyECDSA) { index, vault in
                    Button {
                        selectedVaultPubKey = vault.pubKeyECDSA
                        showVaultSelection = false
                    } label: {
                        vaultSelectionRow(vault)
                    }
                    .buttonStyle(.plain)
                    .commonListItemContainer(index: index, itemsCount: vaults.count)
                    .plainListItem()
                    .background(Theme.colors.bgPrimary)
                }
            }
            .customSectionSpacing(0)
            .listStyle(.plain)
            .buttonStyle(.borderless)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(Theme.colors.bgPrimary)
        }
        .presentationDragIndicator(.visible)
        .presentationCompactAdaptation(.none)
        .presentationBackground { Theme.colors.bgPrimary.padding(.bottom, -1000) }
        .background(Theme.colors.bgPrimary)
    }

    private var vaultSelectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("vaults".localized)
                .foregroundStyle(Theme.colors.textPrimary)
                .font(Theme.fonts.title3)
            Text(vaultSelectionSubtitle)
                .foregroundStyle(Theme.colors.textTertiary)
                .font(Theme.fonts.caption12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 8)
    }

    private var vaultSelectionSubtitle: String {
        let vaultsText = vaults.count == 1 ? "vault".localized : "vaults".localized
        return "\(vaults.count) \(vaultsText)"
    }

    private func vaultSelectionRow(_ vault: Vault) -> some View {
        HStack {
            HStack(spacing: 12) {
                VaultIconTypeView(isFastVault: vault.offersFastSigning)
                    .padding(12)
                    .background(Circle().fill(Theme.colors.bgSurface2))
                    .overlay(
                        Circle()
                            .inset(by: 0.5)
                            .stroke(Theme.colors.borderLight, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(vault.name)
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.bodySMedium)
                        .lineLimit(1)
                    Text(vault.signerPartDescription)
                        .foregroundStyle(Theme.colors.textSecondary)
                        .font(Theme.fonts.priceFootnote)
                }
            }

            Spacer()

            if vault.pubKeyECDSA == selectedVaultPubKey {
                Icon(.check, color: Theme.colors.alertSuccess, size: 24)
            }
        }
        .padding(12)
        .background(vault.pubKeyECDSA == selectedVaultPubKey ? selectedVaultRowBackground : nil)
        .contentShape(Rectangle())
    }

    private var selectedVaultRowBackground: some View {
        Theme.radius.md.shape
            .fill(Theme.colors.bgSurface1)
    }

    private var networksCard: some View {
        Button {
            guard networks.count > 3 else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showAllNetworks.toggle()
            }
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("walletConnectNetworks".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Color.walletConnectTextPrimary)
                    Text("\(networks.count)")
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Color.walletConnectTextSecondary)
                        .frame(minWidth: 28, minHeight: 22)
                        .background(Capsule().fill(Color(hex: "1B3C66")))
                    Spacer()
                    if networks.count > 3 {
                        Image(systemName: showAllNetworks ? "chevron.up" : "chevron.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.walletConnectTextSecondary)
                    }
                }
                .padding(.bottom, 12)

                ForEach(Array(visibleNetworks.enumerated()), id: \.element.id) { index, network in
                    HStack(spacing: 12) {
                        WalletConnectNetworkIcon(display: network, size: 32)
                        Text(network.name)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Color.walletConnectTextPrimary)
                        Spacer()
                    }
                    .frame(height: 44)

                    if index < visibleNetworks.count - 1 {
                        WalletConnectDivider()
                    }
                }

                if networks.count > 3 {
                    Text(showAllNetworks ? "walletConnectShowFewerNetworks".localized : String(format: "walletConnectShowAllNetworks".localized, networks.count))
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Color(hex: "62A9FF"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                }

                namespaceSummary
                    .padding(.top, 12)
            }
            .padding(18)
            .background(Color.walletConnectSurface)
            .clipShape(Theme.radius.lg.shape)
        }
        .buttonStyle(.plain)
    }

    private var namespaceSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            labeledList(title: "walletConnectRequired".localized, namespaces: proposal.requiredNamespaces)
            labeledList(title: "walletConnectOptional".localized, namespaces: proposal.optionalNamespaces)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeledList(title: String, namespaces: [WalletConnectNamespaceRequest]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Color.walletConnectTextTertiary)
            Text(namespaceDescription(namespaces))
                .font(Theme.fonts.caption12)
                .foregroundStyle(Color.walletConnectTextSecondary)
                .lineLimit(4)
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("walletConnectPermissions".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Color.walletConnectTextTertiary)
            permissionRow(icon: "wallet.pass", title: "walletConnectPermissionViewAddresses".localized)
            permissionRow(icon: "signature", title: "walletConnectPermissionRequestSignatures".localized)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func permissionRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.walletConnectTextSecondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.walletConnectSurface))
            Text(title)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Color.walletConnectTextPrimary)
            Spacer()
        }
        .frame(height: 36)
    }

    @ViewBuilder
    private var approvalWarning: some View {
        if let approvalError {
            Text(approvalError.localizedDescription)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.alertWarning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.walletConnectSurface)
                .clipShape(Theme.radius.md.shape)
        }
    }

    private var reminder: some View {
        VStack(alignment: .leading, spacing: 10) {
            WalletConnectDivider()
            Text("walletConnectApproveEveryRequest".localized)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Color.walletConnectTextTertiary)
        }
    }

    private var decisionFooter: some View {
        HStack(spacing: 10) {
            PrimaryButton(
                title: "reject".localized,
                isLoading: isRejecting,
                type: .secondary,
                action: reject
            )
            .frame(width: 131)
            .disabled(isApproving || isRejecting)

            PrimaryButton(
                title: "connect".localized,
                isLoading: isApproving,
                type: .primary,
                action: approve
            )
            .disabled(!canApprove)
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 30)
        .background(Color.walletConnectBackground)
    }

    private func namespaceDescription(_ namespaces: [WalletConnectNamespaceRequest]) -> String {
        guard !namespaces.isEmpty else { return "none".localized }
        return namespaces.map { namespace in
            let methods = namespace.methods.isEmpty ? "none".localized : namespace.methods.joined(separator: ", ")
            let events = namespace.events.isEmpty ? "none".localized : namespace.events.joined(separator: ", ")
            return "\(namespace.namespace): \(methods); \(events)"
        }.joined(separator: "\n")
    }

    private func approve() {
        guard let selectedVault else { return }
        isApproving = true
        Task { @MainActor in
            do {
                try await coordinator.approvePendingProposal(with: selectedVault)
            } catch {
                actionError = error
            }
            isApproving = false
        }
    }

    private func reject() {
        isRejecting = true
        Task { @MainActor in
            do {
                try await coordinator.rejectPendingProposal()
            } catch {
                actionError = error
            }
            isRejecting = false
        }
    }
}
