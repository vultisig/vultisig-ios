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
        
        createCircleGroup(vault: vault, groups: groups)
    }
    
    private func createCircleGroup(vault: Vault, groups: [GroupedChain]) {
        let chain: Chain = .ethereum
        let address = vault.circleWalletAddress ?? ""
        
        let circleAsset = TokensStore.TokenSelectionAssets.first(where: { $0.chain == chain && $0.contractAddress.lowercased() == CircleConstants.usdcMainnet.lowercased() }) ?? CoinMeta(
            chain: chain,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: CircleConstants.usdcMainnet,
            isNativeToken: false
        )
        
        // Use CoinFactory to create the coin with correct hexPublicKey and hexChainCode
        let circleCoin = try? CoinFactory.create(
            asset: circleAsset,
            publicKeyECDSA: vault.pubKeyECDSA,
            publicKeyEdDSA: vault.pubKeyEdDSA,
            hexChainCode: vault.hexChainCode,
            isDerived: false
        )
        
        if let circleCoin = circleCoin, !address.isEmpty {
            circleCoin.address = address
        }
        
        guard let circleCoin else {
            self.groups = groups
            return
        }
        
        let group = GroupedChain(
            chain: chain,
            address: address,
            logo: "circle-logo",
            count: 1,
            coins: [circleCoin],
            name: "Circle"
        )
        
        var allGroups = groups
        allGroups.insert(group, at: 0)
        self.groups = allGroups
    }
}
