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

        self.groups = groups

        // Circle requires Ethereum chain available (not necessarily as a DeFi chain)
        if vault.chains.contains(.ethereum) {
            createCircleGroup(vault: vault, groups: groups)
        }
    }

    private func createCircleGroup(vault: Vault, groups: [GroupedChain]) {
        // Check if Circle is enabled in the vault settings
        guard vault.isCircleEnabled else { return }

        let chain: Chain = .ethereum
        let address = vault.circleWalletAddress ?? "" // If there is no address you will be able to create one, after refresh it will be updated

        let circleAsset = CoinMeta(
            chain: chain,
            ticker: "USDC",
            logo: "usdc",
            decimals: 6,
            priceProviderId: "usd-coin",
            contractAddress: CircleConstants.usdcMainnet,
            isNativeToken: false
        )

        var circleCoin: Coin?
        do {
            var pubKeyECDSA = vault.pubKeyECDSA
            var isDerived = false

            if vault.libType == .KeyImport {
                if let ethKey = vault.chainPublicKeys.first(where: { $0.chain == .ethereum })?.publicKeyHex {
                    pubKeyECDSA = ethKey
                    isDerived = true
                }
            }

            // Use CoinFactory to create the coin with correct hexPublicKey and hexChainCode
            circleCoin = try CoinFactory.create(
                asset: circleAsset,
                publicKeyECDSA: pubKeyECDSA,
                publicKeyEdDSA: vault.pubKeyEdDSA,
                hexChainCode: vault.hexChainCode,
                isDerived: isDerived
            )
        } catch {
            print("Error creating Circle Coin: \(error.localizedDescription)")
            return
        }

        if let circleCoin = circleCoin, !address.isEmpty {
            circleCoin.address = address
        }

        guard let circleCoin else {
            print("Error creating Circle Coin")
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
