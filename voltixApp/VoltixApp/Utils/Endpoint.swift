//
//  Endpoint.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-05.
//

import Foundation

class Endpoint {
    
    static let voltixApiProxy = "https://api.voltix.org"
    static let voltixRouter = "https://api.voltix.org/router"
    static let broadcastTransactionThorchainNineRealms = "https://thornode.ninerealms.com/cosmos/tx/v1beta1/txs"
    
    static func fetchAccountNumberThorchainNineRealms(_ address: String) -> String {
        "https://thornode.ninerealms.com/auth/accounts/\(address)"
    }
    
    static func fetchAccountBalanceThorchainNineRealms(address: String) -> String {
        "https://thornode.ninerealms.com/cosmos/bank/v1beta1/balances/\(address)"
    }
    
    static func fetchSwaoQuoteThorchainNineRealms(address: String, fromAsset: String, toAsset: String, amount: String) -> URL {
        "https://thornode.ninerealms.com/thorchain/quote/swap?from_asset=\(fromAsset)&to_asset=\(toAsset)&amount=\(amount)&destination=\(address)".asUrl
    }
    
    static func fetchCoinPaprikaQuotes(_ quotes: String) -> String {
        "https://api.coinpaprika.com/v1/tickers?quotes=\(quotes)"
    }
    
    static let avalancheServiceRpcService = "https://avalanche-c-chain-rpc.publicnode.com"
    
    static let bscServiceRpcService = "https://bsc-rpc.publicnode.com"
    
    static let ethServiceRpcService = "https://ethereum-rpc.publicnode.com"
    
    static let solanaServiceAlchemyRpc = "https://solana-rpc.publicnode.com"
    
    static func bitcoinLabelTxHash(_ value: String) -> String {
        "https://mempool.space/tx/\(value)"
    }
    
    static func litecoinLabelTxHash(_ value: String) -> String {
        "https://litecoinspace.org/tx/\(value)"
    }
    
    static func blockchairStats(_ chainName: String) -> URL {
        "\(voltixApiProxy)/blockchair/\(chainName)/stats".asUrl
    }
    
    static func blockchairBroadcast(_ chainName: String) -> URL {
        "\(voltixApiProxy)/blockchair/\(chainName)/push/transaction".asUrl
    }
    
    static func blockchairDashboard(_ address: String, _ coinName: String) -> URL {
        "\(voltixApiProxy)/blockchair/\(coinName)/dashboards/address/\(address)".asUrl
    }
    
    static func ethereumLabelTxHash(_ value: String) -> String {
        "https://etherscan.io/tx/\(value)"
    }
    
    static func fetchCryptoPrices(coin: String, fiat: String) -> String {
        "https://api.coingecko.com/api/v3/simple/price?ids=\(coin)&vs_currencies=\(fiat)"
    }
    
    static func fetchBitcoinTransactions(_ userAddress: String) -> String {
        "https://mempool.space/api/address/\(userAddress)/txs"
    }
    
    static func fetchLitecoinTransactions(_ userAddress: String) -> String {
        "https://litecoinspace.org/api/address/\(userAddress)/txs"
    }
    
    static func bscLabelTxHash(_ value: String) -> String {
        "https://bscscan.com/tx/\(value)"
    }
    
    static func fetchCosmosAccountBalance(address: String) -> String{
        "https://cosmos-rest.publicnode.com/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchCosmosAccountNumber(_ address: String) -> String {
        "https://cosmos-rest.publicnode.com/cosmos/auth/v1beta1/accounts/\(address)"
    }
    
    static let broadcastCosmosTransaction = "https://cosmos-rest.publicnode.com/cosmos/tx/v1beta1/txs"
    
    static func getExplorerURL(chainTicker: String, txid: String) -> String{
        switch chainTicker {
        case "BTC":
            return "https://blockchair.com/bitcoin/transaction/\(txid)"
        case "BCH":
            return "https://blockchair.com/bitcoin-cash/transaction/\(txid)"
        case "LTC":
            return "https://blockchair.com/litecoin/transaction/\(txid)"
        case "DOGE":
            return "https://blockchair.com/dogecoin/transaction/\(txid)"
        case "RUNE":
            return "https://runescan.io/tx/\(txid)"
        case "SOL":
            return "https://explorer.solana.com/tx/\(txid)"
        case "ETH":
            return "https://etherscan.io/tx/\(txid)"
        case "UATOM":
            return "https://www.mintscan.io/cosmos/tx/\(txid)"
        case "AVAX":
            return "https://snowtrace.io/tx/\(txid)"
        case "BNB":
            return "https://bscscan.com/tx/\(txid)"
        default:
            return ""
        }
    }
    
    static func getExplorerByAddressURL(chainTicker:String, address:String) -> String? {
        switch chainTicker {
        case "BTC":
            return "https://blockchair.com/bitcoin/address/\(address)"
        case "BCH":
            return "https://blockchair.com/bitcoin-cash/address/\(address)"
        case "LTC":
            return "https://blockchair.com/litecoin/address/\(address)"
        case "DOGE":
            return "https://blockchair.com/dogecoin/address/\(address)"
        case "RUNE":
            return "https://runescan.io/address/\(address)"
        case "SOL":
            return "https://explorer.solana.com/address/\(address)"
        case "ETH":
            return "https://etherscan.io/address/\(address)"
        case "UATOM":
            return "https://www.mintscan.io/cosmos/address/\(address)"
        case "AVAX":
            return "https://snowtrace.io/address/\(address)"
        case "BNB":
            return "https://bscscan.com/address/\(address)"
        default:
            return nil
        }
    }
    
    static func getExplorerByAddressURLByGroup(chain: Chain?, address: String) -> String? {
        switch chain {
        case .thorChain:
            return "https://runescan.io/address/\(address)"
        case .solana:
            return "https://explorer.solana.com/address/\(address)"
        case .ethereum:
            return "https://etherscan.io/address/\(address)"
        case .gaiaChain:
            return "https://www.mintscan.io/cosmos/address/\(address)"
        case .avalanche:
            return "https://snowtrace.io/address/\(address)"
        case .bscChain:
            return "https://bscscan.com/address/\(address)"
        case .bitcoin:
            return "https://www.blockchain.com/btc/address/\(address)"
        case .bitcoinCash:
            return "https://explorer.bitcoin.com/bch/address/\(address)"
        case .litecoin:
            return "https://blockchair.com/litecoin/address/\(address)"
        case .dogecoin:
            return "https://blockchair.com/dogecoin/address/\(address)"
        default:
            return nil
        }
    }
    
}

fileprivate extension String {
    
    var asUrl: URL {
        return URL(string: self)!
    }
}
