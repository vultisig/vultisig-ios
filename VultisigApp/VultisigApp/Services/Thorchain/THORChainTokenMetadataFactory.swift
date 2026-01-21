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
        } else if asset.starts(with: "x/") {
            chain = "THOR"
            
            if asset == "x/nami-index-nav-thor1mlphkryw5g54yfkrp6xpqzlpv4f8wh6hyw27yyg4z2els8a9gxpqhfhekt-rcpt" {
                symbol = "yRUNE"
                ticker = "yRUNE"
            } else if asset == "x/nami-index-nav-thor1h0hr0rm3dawkedh44hlrmgvya6plsryehcr46yda2vj0wfwgq5xqrs86px-rcpt" {
                symbol = "yTCY"
                ticker = "yTCY"
            } else if asset == "x/ruji" {
                symbol = "RUJI"
                ticker = "ruji"
            } else if asset == "x/staking-ruji" {
                symbol = "sRUJI"
                ticker = "sruji"
            } else if asset == "x/staking-tcy" {
                symbol = "sTCY"
                ticker = "stcy"
            } else {
                symbol = asset
                ticker = asset
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
