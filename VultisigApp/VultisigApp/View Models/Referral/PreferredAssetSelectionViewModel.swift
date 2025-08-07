//
//  PreferredAssetSelectionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/08/2025.
//

import SwiftUI

class PreferredAssetSelectionViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published private var assets: [PreferredAsset] = []
    private let thorchainService: THORChainAPIService
    
    var filteredAssets: [PreferredAsset] {
        guard searchText.isNotEmpty else { return assets }
        return assets.filter { $0.asset.ticker.localizedCaseInsensitiveContains(searchText) }
    }
    
    init(thorchainService: THORChainAPIService = .init()) {
        self.thorchainService = thorchainService
    }
    
    func setup() async {
        await MainActor.run { isLoading = true }
        do {
            let pools = try await thorchainService.getPools()
            let assets: [PreferredAsset] = pools.compactMap { pool -> PreferredAsset? in
                PreferredAssetFactory.createCoin(from: pool.asset, decimals: pool.decimals)
            }
            
            await MainActor.run { self.assets = assets }
        } catch {
            // Will show empty state
            print("No pools found: \(error)")
        }
        await MainActor.run { isLoading = false }
    }
}

struct PreferredAsset: Identifiable {
    var id: CoinMeta { asset }
    let thorchainAsset: String
    let asset: CoinMeta
}

enum PreferredAssetFactory {
    static func createCoin(from asset: String, decimals: Int? = nil) -> PreferredAsset? {
        let splitAsset = asset.split(separator: ".")
        
        let chain = String(splitAsset[safe: 0] ?? "")
        let assetPart = splitAsset[safe: 1]
        var symbol = chain
        var contractAddress = ""
        
        if let assetPart {
            if assetPart.contains("-") {
                let split = assetPart.split(separator: "-")
                symbol = String(split[0])
                contractAddress = String(split[1])
            } else {
                symbol = String(assetPart)
                contractAddress = assetPart.lowercased()
            }
        }
        
        let appChain = Chain.allCases.first { $0.swapAsset == chain }
        guard let appChain else { return nil }
        
        let coin = CoinMeta(
            chain: appChain,
            ticker: symbol.uppercased(),
            logo: symbol.lowercased(),
            decimals: decimals ?? 6,
            priceProviderId: "",
            contractAddress: contractAddress,
            isNativeToken: contractAddress.isEmpty
        )
        
        return PreferredAsset(thorchainAsset: asset, asset: coin)
    }
}
