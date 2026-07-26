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

    private var items: [DefiMainItem] {
        viewModel.filteredItems(in: vault)
    }

    var body: some View {
        Group {
            if !items.isEmpty {
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
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    handleSelection(item)
                } label: {
                    cell(for: item)
                        .commonListItemContainer(
                            index: index,
                            itemsCount: items.count
                        )
                }
            }
        }
        .commonListContainer()
    }

    @ViewBuilder
    private func cell(for item: DefiMainItem) -> some View {
        switch item {
        case .yield(let providerID):
            DefiYieldProviderRow(vault: vault, providerID: providerID)
        case .chain(let chain):
            DefiChainCellView(chain: chain, vault: vault)
        }
    }

    private func handleSelection(_ item: DefiMainItem) {
        switch item {
        case .yield(let providerID):
            guard enableUsdcIfNeeded() else { return }
            router.navigate(to: YieldRoute.main(vault: vault, providerID: providerID))
        case .chain(let chain):
            switch chain {
            case .thorChain, .mayaChain, .terra, .terraClassic, .qbtc, .ton, .solana:
                router.navigate(to: VaultRoute.defiChain(chain: chain, vault: vault))
            case .tron:
                router.navigate(to: TronRoute.main(vault: vault))
            default:
                break
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
