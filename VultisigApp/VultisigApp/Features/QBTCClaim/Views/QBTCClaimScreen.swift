//
//  QBTCClaimScreen.swift
//  VultisigApp
//
//  Top-level screen for the QBTC claim flow. Owns the gate state,
//  selection state, and orchestrator. Sub-views are dispatched by
//  `viewModel.state`. Phase-specific UI for the .claiming state is
//  driven by `viewModel.orchestrator.phase`.
//

import SwiftUI

struct QBTCClaimScreen: View {
    @StateObject private var viewModel: QBTCClaimViewModel
    @Environment(\.openURL) private var openURL

    init(vault: Vault) {
        _viewModel = StateObject(wrappedValue: QBTCClaimViewModel(vault: vault))
    }

    var body: some View {
        Screen {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .screenTitle("qbtcClaimTitle".localized)
        .task {
            if case .loading = viewModel.state {
                await viewModel.load()
            }
        }
        .crossPlatformSheet(isPresented: $viewModel.isPasswordSheetPresented) {
            FastVaultEnterPasswordView(
                password: $viewModel.fastVaultPassword,
                vault: viewModel.vault,
                onSubmit: { viewModel.startClaim() }
            )
        }
    }

    /// `nil` when the QBTC chain has no public explorer wired up (today
    /// `ExplorerLinkBuilder.getExplorerURL(chain: .qbtc, ...)` returns "").
    /// The result view hides its "View on explorer" CTA when this is `nil`.
    private func explorerURL(for txHash: String) -> URL? {
        let raw = ExplorerLinkBuilder.getExplorerURL(chain: .qbtc, txid: txHash)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            QBTCClaimLoadingView()
        case .blocked(let reason):
            QBTCClaimBlockedView(reason: reason)
        case .selecting:
            QBTCClaimSelectionView(
                viewModel: viewModel,
                errorMessage: viewModel.lastClaimError
            )
        case .awaitingPeer:
            QBTCClaimAwaitingPeerView(viewModel: viewModel)
        case .claiming:
            QBTCClaimRunningView(
                phase: viewModel.orchestrator.phase,
                coinLogo: viewModel.qbtcCoin?.logo ?? "qbtc"
            )
        case .done(let result):
            QBTCClaimResultView(
                result: result,
                qbtcCoin: viewModel.qbtcCoin,
                explorerURL: explorerURL(for: result.txHashHex),
                onOpenExplorer: { url in openURL(url) }
            )
        }
    }
}
