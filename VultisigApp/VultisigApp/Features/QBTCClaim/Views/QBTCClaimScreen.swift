//
//  QBTCClaimScreen.swift
//  VultisigApp
//
//  Selection screen for the QBTC claim flow. Owns the gate state +
//  selection state. Pair / keysign / done are separate router-managed
//  screens reached via `QBTCClaimRoute`; this screen pushes them by
//  observing the view model's `pendingPairContext` /
//  `pendingKeysignContext` signals.
//

import SwiftUI

struct QBTCClaimScreen: View {
    @Environment(\.router) var router
    @StateObject private var viewModel: QBTCClaimViewModel

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
        .onChange(of: viewModel.pendingPairContext) { _, context in
            guard let context else { return }
            viewModel.pendingPairContext = nil
            router.navigate(
                to: QBTCClaimRoute.pair(
                    vault: viewModel.vault,
                    keysignPayload: context.keysignPayload,
                    session: context.session,
                    qbtcCoin: context.qbtcCoin,
                    selectedUtxos: context.selectedUtxos
                )
            )
        }
        .onChange(of: viewModel.pendingKeysignContext) { _, context in
            guard let context else { return }
            viewModel.pendingKeysignContext = nil
            router.navigate(
                to: QBTCClaimRoute.keysign(
                    vault: viewModel.vault,
                    btcCoin: context.btcCoin,
                    qbtcCoin: context.qbtcCoin,
                    selectedUtxos: context.selectedUtxos,
                    fastVaultPassword: context.fastVaultPassword,
                    session: nil,
                    participants: []
                )
            )
        }
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
        }
    }
}
