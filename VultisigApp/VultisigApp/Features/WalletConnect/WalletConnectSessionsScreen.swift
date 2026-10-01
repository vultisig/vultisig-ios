//
//  WalletConnectSessionsScreen.swift
//  VultisigApp
//

import SwiftData
import SwiftUI

struct WalletConnectSessionsScreen: View {
    @Query(sort: \Vault.order) private var vaults: [Vault]
    @StateObject private var viewModel = WalletConnectSessionsViewModel()
    @State private var expandedNetworkTopics = Set<String>()
#if DEBUG
    @State private var showDebugURIAlert = false
    @State private var debugURI = ""
#endif

    private var showError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header
#if DEBUG
                    debugAddButton
#endif
                    sessionsContent
                    helperNote
                }
                .padding(.top, 4)
            }
        }
        .background(Color.walletConnectPageBackground)
        .screenTitle("walletConnectSessions".localized)
        .onAppear { viewModel.load() }
        .onReceive(NotificationCenter.default.publisher(for: .walletConnectSessionBindingsDidChange)) { _ in
            viewModel.load()
        }
        .alert("error".localized, isPresented: showError) {
            Button("ok".localized, role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "walletConnectDisconnectFailed".localized)
        }
#if DEBUG
        .alert("Add WalletConnect URI", isPresented: $showDebugURIAlert) {
            TextField("wc:...", text: $debugURI)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {
                debugURI = ""
            }
            Button("Accept") {
                let uri = debugURI
                debugURI = ""
                Task { await viewModel.pairDebugURI(uri) }
            }
        } message: {
            Text("Paste a WalletConnect URI for debug testing.")
        }
#endif
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("walletConnectSessions".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Color.walletConnectTextPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text("walletConnectSessionsDescription".localized)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Color.walletConnectTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(String(format: "walletConnectActiveConnections".localized, viewModel.bindings.count))
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Color.walletConnectTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 18)
        }
    }

#if DEBUG
    private var debugAddButton: some View {
        PrimaryButton(
            title: "Add",
            isLoading: viewModel.isPairingDebugURI,
            type: .secondary,
            size: .mini
        ) {
            showDebugURIAlert = true
        }
        .disabled(viewModel.isPairingDebugURI)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
#endif

    @ViewBuilder
    private var sessionsContent: some View {
        if viewModel.bindings.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 18) {
                ForEach(viewModel.bindings, id: \.topic) { binding in
                    sessionCard(binding)
                }
            }
        }
    }

    private var emptyState: some View {
        Text("walletConnectSessionsEmpty".localized)
            .font(Theme.fonts.bodySRegular)
            .foregroundStyle(Color.walletConnectTextSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Color.walletConnectCard)
            .overlay(Theme.radius.xl.shape.stroke(Color.walletConnectBorder, lineWidth: 1))
            .clipShape(Theme.radius.xl.shape)
    }

    private func sessionCard(_ binding: WalletConnectSessionBinding) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                WalletConnectDAppAvatar(name: binding.dappName, iconURL: binding.dappIconURL, size: 48)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(binding.dappName)
                            .font(Theme.fonts.bodyMMedium)
                            .foregroundStyle(Color.walletConnectTextPrimary)
                            .lineLimit(1)
                        Circle()
                            .fill(Color.walletConnectVaultAccent)
                            .frame(width: 9, height: 9)
                        Text("walletConnectConnected".localized)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Color.walletConnectTextSecondary)
                    }
                    Text(binding.dappURL)
                        .font(Theme.fonts.caption12)
                        .foregroundStyle(Color.walletConnectTextTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }

            WalletConnectDivider()

            vaultSection(for: binding)

            WalletConnectDivider()

            networksSection(for: binding)

            WalletConnectDivider()

            WalletConnectDestructiveButton(
                title: "walletConnectDisconnect".localized,
                isLoading: viewModel.removingTopic == binding.topic
            ) {
                Task { await viewModel.remove(binding) }
            }
            .disabled(viewModel.removingTopic != nil)
        }
        .padding(18)
        .background(Color.walletConnectCard)
        .overlay(Theme.radius.xl.shape.stroke(Color.walletConnectBorder, lineWidth: 1))
        .clipShape(Theme.radius.xl.shape)
        .accessibilityElement(children: .combine)
    }

    private func vaultSection(for binding: WalletConnectSessionBinding) -> some View {
        HStack(spacing: 12) {
            WalletConnectVaultIcon(style: vault(for: binding)?.offersFastSigning == true ? .fast : .secure)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(vaultName(for: binding))
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Color.walletConnectTextPrimary)
                    .lineLimit(1)
                Text(vaultSubtitle(for: binding))
                    .font(Theme.fonts.caption12)
                    .foregroundStyle(Color.walletConnectTextTertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private func networksSection(for binding: WalletConnectSessionBinding) -> some View {
        let networks = WalletConnectChainDisplay.unique(from: binding.approvedChains)
        let isExpanded = expandedNetworkTopics.contains(binding.topic)
        let visibleNetworks = isExpanded ? networks : Array(networks.prefix(3))

        return Button {
            guard networks.count > 3 else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                if isExpanded {
                    expandedNetworkTopics.remove(binding.topic)
                } else {
                    expandedNetworkTopics.insert(binding.topic)
                }
            }
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("walletConnectApprovedNetworks".localized)
                        .font(Theme.fonts.bodySMedium)
                        .foregroundStyle(Color.walletConnectTextPrimary)
                    Spacer()
                    if networks.count > 1 {
                        Text("\(networks.count)")
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Color.walletConnectTextSecondary)
                            .frame(minWidth: 28, minHeight: 22)
                            .background(Capsule().fill(Color(hex: "1B3C66")))
                    }
                    if networks.count > 3 {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.walletConnectTextSecondary)
                    }
                }
                .padding(.bottom, networks.isEmpty ? 0 : 10)

                if networks.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "network")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.walletConnectTextSecondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.walletConnectSurface))
                        Text("walletConnectApprovedNetworksUnknown".localized)
                            .font(Theme.fonts.bodySRegular)
                            .foregroundStyle(Color.walletConnectTextTertiary)
                        Spacer()
                    }
                } else {
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
                        Text(isExpanded ? "walletConnectShowFewerNetworks".localized : String(format: "walletConnectShowAllNetworks".localized, networks.count))
                            .font(Theme.fonts.bodySMedium)
                            .foregroundStyle(Color(hex: "62A9FF"))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var helperNote: some View {
        VStack(alignment: .leading, spacing: 12) {
            WalletConnectDivider()
            Text("walletConnectSessionsHelperNote".localized)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Color.walletConnectTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }

    private func vault(for binding: WalletConnectSessionBinding) -> Vault? {
        vaults.first { $0.pubKeyECDSA == binding.vaultPubKeyECDSA }
    }

    private func vaultName(for binding: WalletConnectSessionBinding) -> String {
        vault(for: binding)?.name ?? "walletConnectUnknownVault".localized
    }

    private func vaultSubtitle(for binding: WalletConnectSessionBinding) -> String {
        vault(for: binding)?.signerPartDescription
            ?? String(format: "walletConnectSessionMetadata".localized, binding.createdAt.formatted(date: .abbreviated, time: .shortened), binding.topic)
    }
}

#if DEBUG
#Preview {
    WalletConnectSessionsScreen()
}
#endif
