//
//  THORChainTokenMetadataFactory.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/08/2025.
//

enum THORChainTokenMetadataFactory {
    static func create(asset: String) -> THORChainTokenMetadata {
        let decimals = 8
        var chain = ""
        var symbol = ""
        var ticker = ""
        var logo = ""
        
        if asset.contains(".") {
            // Switch asset: thor.fuzn
            let parts = asset.split(separator: ".")
            if parts.count >= 2 {
                chain = parts[0].uppercased()
                symbol = parts[1].uppercased()
                ticker = parts[1].lowercased()
            }
        } else if asset.contains("-") {
            let parts = asset.split(separator: "-")
            if parts.count >= 2 {
                chain = parts[0].uppercased()
                symbol = parts[1].uppercased()
                ticker = parts[1].lowercased()
            }
        } else {
            // Native THORChain asset (e.g., rune)
            chain = "THOR"
            symbol = asset.uppercased()
            ticker = asset.lowercased()
        }
        
        logo = ticker.replacingOccurrences(of: "/", with: "") // It will use whatever is in our asset list
        
        return THORChainTokenMetadata(chain: chain, ticker: ticker, symbol: symbol, decimals: decimals, logo: logo)
    }
}
