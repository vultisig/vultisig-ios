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
        .withLoading(text: "qbtcClaimLoading".localized, isLoading: $viewModel.isLoading)
        .task {
            // First entry: kick the gate-check pipeline. `load()` is
            // idempotent — calling it on subsequent re-appears is a
            // no-op against in-flight state and re-runs cleanly otherwise.
            await viewModel.load()
        }
        .crossPlatformSheet(isPresented: $viewModel.isPasswordSheetPresented) {
            FastVaultEnterPasswordView(
                password: $viewModel.fastVaultPassword,
                vault: viewModel.vault,
                onSubmit: { viewModel.startClaim() }
            )
        }
    }

    /// `nil` when the URL string fails to parse — `ExplorerLinkBuilder`
    /// now returns the canonical `https://qbtc-explorer.vercel.app/qbtc/tx/<txid>`
    /// for QBTC, so the result view's "View on explorer" CTA is wired up.
    private func explorerURL(for txHash: String) -> URL? {
        let raw = ExplorerLinkBuilder.getExplorerURL(chain: .qbtc, txid: txHash)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
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
