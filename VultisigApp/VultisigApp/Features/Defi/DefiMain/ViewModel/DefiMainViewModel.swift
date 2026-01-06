//
//  DefiMainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import Foundation

@MainActor
final class DefiMainViewModel: ObservableObject {
    @Published private var groups = [GroupedChain]()
    @Published var searchText: String = ""
    
    private let groupedChainListBuilder = GroupedChainListBuilder()
    
    init() {}
    
    var filteredGroups: [GroupedChain] {
        guard !searchText.isEmpty else {
            return groups
        }
        return groups.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.nativeCoin.ticker.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    func groupChains(vault: Vault) {
        let groups = self.groupedChainListBuilder
            .groupChains(
                for: vault,
                sortedBy: \.defiBalanceInFiatDecimal
            ) { vault.defiChains.contains($0.nativeCoin.chain) && CoinAction.defiChains.contains($0.nativeCoin.chain) }
        
        // Add Circle Group
        var allGroups = groups
        let circleAddress = vault.circleWalletAddress ?? ""
        allGroups.insert(createCircleGroup(address: circleAddress), at: 0)
        
        self.groups = allGroups
    }
    
    private func createCircleGroup(address: String) -> GroupedChain {
        let circleAsset = TokensStore.TokenSelectionAssets.first(where: { $0.chain == .ethereum && $0.ticker == "USDC" }) ?? CoinMeta(
            chain: .ethereum,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            isNativeToken: false
        )
        
        let circleCoin = Coin(asset: circleAsset, address: address, hexPublicKey: "")
        
        return GroupedChain(
            chain: .ethereum,
            address: address,
            logo: "circle-logo",
            count: 1,
            coins: [circleCoin],
            name: "Circle"
        )
    }
}
