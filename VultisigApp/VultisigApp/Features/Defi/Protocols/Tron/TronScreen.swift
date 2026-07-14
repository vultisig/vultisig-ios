//
//  TronScreen.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI
import BigInt

struct TronScreen: View {
    let vault: Vault

    @StateObject private var model = TronViewModel()

    var body: some View {
        content
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                await loadData()
            }
    }

    @ViewBuilder
    var content: some View {
        if model.missingTrx {
            TronMissingTrxScreen()
        } else {
            Screen {
                // Show dashboard immediately (cards show their own loading states)
                TronDashboardView(vault: vault, model: model, onRefresh: { await loadData(forceRefresh: true) })
            }
            .screenTitle("tronTitle".localized)
            .screenEdgeInsets(.init(leading: 0, trailing: 0))
        }
    }

    private func loadData(forceRefresh: Bool = false) async {
        // Check if vault has TRX
        guard let trxCoin = TronViewLogic.getTrxCoin(vault: vault) else {
            await MainActor.run {
                model.missingTrx = true
                model.isLoading = false
                model.isLoadingBalance = false
                model.isLoadingResources = false
            }
            return
        }

        let address = trxCoin.address
        let tronService = TronService.shared

        // Serve fresh-cached data immediately without a spinner. Only show
        // loading skeletons when the cache is cold/stale or an explicit
        // refresh was requested.
        let cachedAccount = forceRefresh ? nil : await tronService.cachedAccount(for: address)
        let cachedResource = forceRefresh ? nil : await tronService.cachedAccountResource(for: address)

        await MainActor.run {
            model.missingTrx = false
            model.error = nil
            model.isLoading = cachedAccount == nil || cachedResource == nil
            model.isLoadingBalance = cachedAccount == nil
            model.isLoadingResources = cachedResource == nil

            if let cachedAccount {
                model.apply(account: cachedAccount)
            }

            if let cachedResource {
                model.apply(resource: cachedResource)
            }
        }

        // Use structured concurrency for proper cancellation handling
        await withTaskGroup(of: Void.self) { group in
            // Task 1: Fetch account info (balance data)
            group.addTask {
                do {
                    let account = try await tronService.getAccount(address: address, forceRefresh: forceRefresh)
                    await self.model.apply(account: account)
                } catch {
                    if !(error is CancellationError) {
                        await MainActor.run {
                            self.model.error = error
                            self.model.isLoadingBalance = false
                        }
                    }
                }
            }

            // Task 2: Fetch resource info (bandwidth/energy)
            group.addTask {
                do {
                    let resource = try await tronService.getAccountResource(address: address, forceRefresh: forceRefresh)
                    await self.model.apply(resource: resource)
                } catch {
                    if !(error is CancellationError) {
                        await MainActor.run {
                            self.model.error = error
                            self.model.isLoadingResources = false
                        }
                    }
                }
            }
        }

        // Clear global loading state after task group completes
        await MainActor.run { model.isLoading = false }
        guard !Task.isCancelled else { return }

        // Persist the frozen/unfreezing balance into `Coin.stakedBalance` so the
        // DeFi portfolio main screen (which reads the persisted value) stays in
        // sync with this live detail view instead of diverging. Run this only
        // after the detail data is populated so its network calls never gate cards.
        await BalanceService.shared.updateBalance(for: trxCoin)
    }
}
