//
//  WalletConnectSessionsScreen.swift
//  VultisigApp
//

import SwiftData
import SwiftUI

struct WalletConnectSessionsScreen: View {
    @Query(sort: \Vault.order) private var vaults: [Vault]
    @StateObject private var viewModel = WalletConnectSessionsViewModel()

    private var showError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    description
                    sessionsSection
                }
            }
        }
        .screenTitle("walletConnectSessions".localized)
        .alert("error".localized, isPresented: showError) {
            Button("ok".localized, role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "walletConnectDisconnectFailed".localized)
        }
    }

    private var description: some View {
        Text("walletConnectSessionsDescription".localized)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    @ViewBuilder
    private var sessionsSection: some View {
        SettingsSectionView(title: "walletConnectSessions".localized) {
            if viewModel.bindings.isEmpty {
                emptyState
            } else {
                ForEach(Array(viewModel.bindings.enumerated()), id: \.element.topic) { index, binding in
                    sessionRow(binding)
                        .commonListItemContainer(index: index, itemsCount: viewModel.bindings.count)
                }
            }
        }
    }

    private var emptyState: some View {
        Text("walletConnectSessionsEmpty".localized)
            .font(Theme.fonts.bodySRegular)
            .foregroundStyle(Theme.colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(24)
    }

    private func sessionRow(_ binding: WalletConnectSessionBinding) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(binding.dappName)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textPrimary)
                    .lineLimit(1)

                Text(binding.dappURL)
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .lineLimit(1)

                Text(vaultDisplayText(for: binding))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textSecondary)
                    .lineLimit(1)

                Text(metadataText(for: binding))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            PrimaryButton(
                title: "walletConnectDisconnect".localized,
                isLoading: viewModel.removingTopic == binding.topic,
                type: .secondary,
                size: .mini
            ) {
                Task { await viewModel.remove(binding) }
            }
            .fixedSize()
            .disabled(viewModel.removingTopic != nil)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func vaultDisplayText(for binding: WalletConnectSessionBinding) -> String {
        let vaultName = vaults.first { $0.pubKeyECDSA == binding.vaultPubKeyECDSA }?.name
            ?? "walletConnectUnknownVault".localized
        return String(format: "walletConnectBoundVault".localized, vaultName)
    }

    private func metadataText(for binding: WalletConnectSessionBinding) -> String {
        String(
            format: "walletConnectSessionMetadata".localized,
            binding.createdAt.formatted(date: .abbreviated, time: .shortened),
            binding.topic
        )
    }
}

#if DEBUG
#Preview {
    WalletConnectSessionsScreen()
}
#endif
