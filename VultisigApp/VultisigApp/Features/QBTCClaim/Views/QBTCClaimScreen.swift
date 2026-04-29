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
        case .claiming:
            QBTCClaimRunningView(phase: viewModel.orchestrator.phase)
        case .done(let result):
            QBTCClaimResultView(
                result: result,
                qbtcCoin: viewModel.qbtcCoin,
                onOpenExplorer: openExplorer
            )
        }
    }

    private func openExplorer(_ txHash: String) {
        guard let coin = viewModel.qbtcCoin else { return }
        let url = "\(Endpoint.qbtcRestBaseURL.replacingOccurrences(of: "/qbtc-rpc", with: ""))/tx/\(txHash)"
        if let parsed = URL(string: url) {
            openURL(parsed)
        }
        _ = coin
    }
}
