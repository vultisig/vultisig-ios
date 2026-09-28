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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                namespaceSection(title: "walletConnectRequired".localized, namespaces: proposal.requiredNamespaces)
                namespaceSection(title: "walletConnectOptional".localized, namespaces: proposal.optionalNamespaces)
                vaultSelector
                approvalWarning
                actions
            }
            .padding(24)
        }
        .background(Theme.colors.bgPrimary)
        .onAppear {
            if selectedVaultPubKey.isEmpty {
                selectedVaultPubKey = vaults.first?.pubKeyECDSA ?? ""
            }
        }
        .withError(error: $actionError, errorType: .warning) {
            actionError = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("walletConnect".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(proposal.name)
                .font(Theme.fonts.subtitle)
                .foregroundStyle(Theme.colors.textPrimary)
            Text(proposal.displayHost)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textTertiary)

            if let verificationStatus = proposal.verificationStatus {
                Text(String(format: "walletConnectVerification".localized, verificationStatus))
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
            }
        }
    }

    private func namespaceSection(title: String, namespaces: [WalletConnectNamespaceRequest]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.fonts.subtitle)
                .foregroundStyle(Theme.colors.textPrimary)

            if namespaces.isEmpty {
                Text("none".localized)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
            } else {
                ForEach(Array(namespaces.enumerated()), id: \.offset) { _, namespace in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(namespace.namespace)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Theme.colors.textPrimary)
                        labeledList(title: "walletConnectChains".localized, values: namespace.chains)
                        labeledList(title: "walletConnectMethods".localized, values: namespace.methods)
                        labeledList(title: "walletConnectEvents".localized, values: namespace.events)
                    }
                    .padding(12)
                    .background(Theme.colors.bgSurface1)
                    .clipShape(Theme.radius.md.shape)
                }
            }
        }
    }

    private func labeledList(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.fonts.caption12)
                .foregroundStyle(Theme.colors.textTertiary)
            Text(values.isEmpty ? "none".localized : values.joined(separator: ", "))
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textPrimary)
        }
    }

    private var vaultSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("walletConnectApproveWithVault".localized)
                .font(Theme.fonts.subtitle)
                .foregroundStyle(Theme.colors.textPrimary)

            Picker("vault".localized, selection: $selectedVaultPubKey) {
                ForEach(vaults, id: \.pubKeyECDSA) { vault in
                    Text(vault.name).tag(vault.pubKeyECDSA)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.colors.textPrimary)
        }
    }

    @ViewBuilder
    private var approvalWarning: some View {
        if let approvalError {
            Text(approvalError.localizedDescription)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.alertWarning)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            PrimaryButton(
                title: "approve".localized,
                isLoading: isApproving,
                type: .primary,
                action: approve
            )
            .disabled(!canApprove)

            PrimaryButton(
                title: "reject".localized,
                isLoading: isRejecting,
                type: .secondary,
                action: reject
            )
            .disabled(isApproving || isRejecting)
        }
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
