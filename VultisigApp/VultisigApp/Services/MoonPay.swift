//
//  MoonPay.swift
//  VultisigApp
//
//  Created by Johnny Luo on 9/5/2025.
//

class MoonPayHelper {
    let walletAddressMap:[String: Chain] = [
        "eth": .ethereum,
        "atom": .gaiaChain,
        "avax_cchain": .avalanche,
        "bch":.bitcoinCash,
        "bnb_bsc":.bscChain,
        "btc":.bitcoin,
        "doge":.dogecoin,
        "dot":.polkadot,
        "dydx_dydx":.dydx,
        "eth_arbitrum":.arbitrum,
        "eth_base":.base,
        "eth_optimism":.optimism,
        "eth_polygon":.polygonV2,
        "ltc":.litecoin,
        "sol":.solana,
        "sui":.sui,
        "ton":.ton,
        "trx":.tron,
        "usdc":.ethereum,
        "usdc_arbitrum":.arbitrum,
        "usdc_base":.base,
        "usdc_cchain":.avalanche,
        "usdc_noble":.noble,
        "usdc_optimism":.optimism,
        "usdc_sol":.solana,
        "usdt":.ethereum,
        "usdt_arbitrum":.arbitrum,
        "usdt_bsc":.bscChain,
        "usdt_optimism":.optimism,
        "usdt_polygon":.polygonV2,
        "usdt_sol":.solana,
        "usdt_ton":.ton,
        "usdt_trx":.tron
    ]
    
    func getWalletAddresses(vault: Vault) -> [String:String]{
        var chainAddresses: [Chain:String] = [:]
        for coin in vault.coins {
            chainAddresses[coin.chain] = coin.address
        }
        var walletAddresses : [String:String] = [:]
        for (k,v) in walletAddressMap {
            walletAddresses[k] = chainAddresses[v]
        }
        return walletAddresses
    }
    func getCurrencyFromChain(chain: Chain) -> String? {
        for (k,v) in walletAddressMap {
            if v == chain {
                return k
            }
        }
        return nil
    }
}
