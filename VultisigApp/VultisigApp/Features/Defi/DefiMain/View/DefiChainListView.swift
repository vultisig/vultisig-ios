//
//  DefiChainListView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "defi-chain-list")

struct DefiChainListView: View {
    @ObservedObject var vault: Vault
    @ObservedObject var viewModel: DefiMainViewModel

    @Environment(\.router) var router

    var onCustomizeChains: () -> Void

    var body: some View {
        Group {
            if !viewModel.filteredGroups.isEmpty {
                chainList
            } else {
                CustomizeChainsActionBanner(
                    showButton: true,
                    onCustomizeChains: onCustomizeChains
                )
            }
        }
    }

    var chainList: some View {
        ForEach(Array(viewModel.filteredGroups.enumerated()), id: \.element.id) { index, group in
            Button {
                if group.name == "Circle" {
                    guard enableUsdcIfNeeded() else { return }
                    router.navigate(to: CircleRoute.main(vault: vault))
                } else {
                    switch group.chain {
                    case .thorChain, .mayaChain:
                        router.navigate(to: VaultRoute.defiChain(group: group, vault: vault))
                    case .tron:
                        router.navigate(to: TronRoute.main(vault: vault))
                    default:
                        break
                    }
                }
            } label: {
                DefiChainCellView(group: group, vault: vault)
                    .commonListItemContainer(
                        index: index,
                        itemsCount: viewModel.filteredGroups.count
                    )
            }
          }
    }

    @discardableResult
    private func enableUsdcIfNeeded() -> Bool {
        let usdcMeta = TokensStore.ethUSDC
        do {
            _ = try CoinService.addIfNeeded(asset: usdcMeta, to: vault, priceProviderId: usdcMeta.priceProviderId)
            return true
        } catch {
            logger.error("Failed to enable USDC: \(error.localizedDescription)")
            return false
        }
    }
}

#Preview {
    DefiChainListView(
        vault: .example,
        viewModel: DefiMainViewModel()
    ) {}
        .environmentObject(VaultDetailViewModel())
}
