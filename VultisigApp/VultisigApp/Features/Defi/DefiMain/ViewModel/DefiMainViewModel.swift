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
        let isSepolia = vault.coins.contains { $0.chain == .ethereumSepolia }
        let chain: Chain = isSepolia ? .ethereumSepolia : .ethereum
        let address = vault.circleWalletAddress ?? ""
        
        allGroups.insert(createCircleGroup(address: address, vault: vault, chain: chain), at: 0)
        
        self.groups = allGroups
    }
    
    private func createCircleGroup(address: String, vault: Vault, chain: Chain) -> GroupedChain {
        let usdcContract = chain == .ethereumSepolia ? CircleConstants.usdcSepolia : CircleConstants.usdcMainnet
        
        let circleAsset = TokensStore.TokenSelectionAssets.first(where: { $0.chain == chain && $0.contractAddress.lowercased() == usdcContract.lowercased() }) ?? CoinMeta(
            chain: chain,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: usdcContract,
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
        
        return GroupedChain(
            chain: chain,
            address: address,
            logo: "circle-logo",
            count: 1,
            coins: [circleCoin!],
            name: "Circle"
        )
    }
}
