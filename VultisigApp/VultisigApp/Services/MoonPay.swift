//
//  MoonPay.swift
//  VultisigApp
//
//  Created by Johnny Luo on 9/5/2025.
//

struct MoonPayToken {
    let currencyCode: String
    let chain: Chain
    let contractAddress: String
}
class MoonPayHelper {
    
    let walletAddressMap = [
        MoonPayToken(currencyCode: "eth", chain: .ethereum, contractAddress: ""),
        MoonPayToken(currencyCode: "eth", chain: .ethereumSepolia, contractAddress: ""),
        MoonPayToken(currencyCode: "atom", chain: .gaiaChain, contractAddress: ""),
        MoonPayToken(currencyCode: "avax_cchain", chain: .avalanche, contractAddress: ""),
        MoonPayToken(currencyCode: "bch", chain: .bitcoinCash, contractAddress: ""),
        MoonPayToken(currencyCode: "bnb_bsc", chain: .bscChain, contractAddress: ""),
        MoonPayToken(currencyCode: "btc", chain: .bitcoin, contractAddress: ""),
        MoonPayToken(currencyCode: "doge", chain: .dogecoin, contractAddress: ""),
        MoonPayToken(currencyCode: "dot", chain: .polkadot, contractAddress: ""),
        MoonPayToken(currencyCode: "dydx_dydx", chain: .dydx, contractAddress: ""),
        MoonPayToken(currencyCode: "eth_arbitrum", chain: .arbitrum, contractAddress: ""),
        MoonPayToken(currencyCode: "eth_base", chain: .base, contractAddress: ""),
        MoonPayToken(currencyCode: "eth_optimism", chain: .optimism, contractAddress: ""),
        MoonPayToken(currencyCode: "eth_polygon", chain: .polygonV2, contractAddress: ""),
        MoonPayToken(currencyCode: "ltc", chain: .litecoin, contractAddress: ""),
        MoonPayToken(currencyCode: "sol", chain: .solana, contractAddress: ""),
        MoonPayToken(currencyCode: "sui", chain: .sui, contractAddress: ""),
        MoonPayToken(currencyCode: "ton", chain: .ton, contractAddress: ""),
        MoonPayToken(currencyCode: "trx", chain: .tron, contractAddress: ""),
        MoonPayToken(currencyCode: "usdc", chain: .ethereum, contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
        MoonPayToken(currencyCode: "usdc_arbitrum", chain: .arbitrum, contractAddress: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831"),
        MoonPayToken(currencyCode: "usdc_base", chain: .base, contractAddress: "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913"),
        MoonPayToken(currencyCode: "usdc_cchain", chain: .avalanche, contractAddress: "0xb97ef9ef8734c71904d8002f8b6bc66dd9c48a6e"),
        MoonPayToken(currencyCode: "usdc_noble", chain: .noble, contractAddress: ""),
        MoonPayToken(currencyCode: "usdc_optimism", chain: .optimism, contractAddress: "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85"),
        MoonPayToken(currencyCode: "usdc_sol", chain: .solana, contractAddress: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"),
        MoonPayToken(currencyCode: "usdt", chain: .ethereum, contractAddress: "0xdAC17F958D2ee523a2206206994597C13D831ec7"),
        MoonPayToken(currencyCode: "usdt_arbitrum", chain: .arbitrum, contractAddress: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9"),
        MoonPayToken(currencyCode: "usdt_bsc", chain: .bscChain, contractAddress: "0x55d398326f99059fF775485246999027B3197955"),
        MoonPayToken(currencyCode: "usdt_optimism", chain: .optimism, contractAddress: "0x94b008aA00579c1307B0EF2c499aD98a8ce58e58"),
        MoonPayToken(currencyCode: "usdt_polygon", chain: .polygonV2, contractAddress: "0xc2132D05D31c914a87C6611C10748AEb04B58e8F"),
        MoonPayToken(currencyCode: "usdt_sol", chain: .solana, contractAddress: "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB"),
        MoonPayToken(currencyCode: "usdt_ton", chain: .ton, contractAddress: "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs"),
        MoonPayToken(currencyCode: "usdt_trx", chain: .tron, contractAddress: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"),
    ]
    
    func getWalletAddresses(vault: Vault) -> [String:String]{
        var chainAddresses: [Chain:String] = [:]
        for coin in vault.coins {
            chainAddresses[coin.chain] = coin.address
        }
        var walletAddresses : [String:String] = [:]
        for item in walletAddressMap {
            walletAddresses[item.currencyCode] = chainAddresses[item.chain]
        }
        return walletAddresses
    }
    func getCurrencyFromChain(chain: Chain,contractAddress: String) -> String? {
        for item in self.walletAddressMap {
            if item.chain == chain  && item.contractAddress == contractAddress {
                return item.currencyCode
            }
        }
        return nil
    }
}
