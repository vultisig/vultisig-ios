//
//  Endpoint.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-05.
//

import Foundation

class Endpoint {
    
    enum SwapChain {
        case thorchain
        case maya
        
        var baseUrl: String {
            switch self {
            case .thorchain:
                return "https://thornode.ninerealms.com/thorchain"
            case .maya:
                return "https://mayanode.mayachain.info/mayachain"
            }
        }
    }
    
    static let vultisigApiProxy = "https://api.vultisig.com"
    static let supportDocumentLink = "https://docs.voltix.org/user-actions/creating-a-vault"
    static let vultisigRelay = "https://api.vultisig.com/router"
    static let broadcastTransactionThorchainNineRealms = "https://thornode.ninerealms.com/cosmos/tx/v1beta1/txs"
    static let broadcastTransactionMayachain = "https://mayanode.mayachain.info/cosmos/tx/v1beta1/txs"
    
    static func fetchBlowfishTransactions(chain: String, network: String) -> String {
        "\(vultisigApiProxy)/blowfish/\(chain)/v0/\(network)/scan/transactions?language=en&method=eth_sendTransaction"
    }
    
    static func fetchAccountNumberThorchainNineRealms(_ address: String) -> String {
        "https://thornode.ninerealms.com/auth/accounts/\(address)"
    }
    
    static let fetchThorchainNetworkInfoNineRealms = "https://thornode.ninerealms.com/thorchain/network"
    
    static func fetchAccountNumberMayachain(_ address: String) -> String {
        "https://mayanode.mayachain.info/auth/accounts/\(address)"
    }
    static func fetchAccountBalanceThorchainNineRealms(address: String) -> String {
        "https://thornode.ninerealms.com/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchAccountBalanceMayachain(address: String) -> String {
        "https://mayanode.mayachain.info/cosmos/bank/v1beta1/balances/\(address)"
    }
    
    static func fetchSwapQuoteThorchain(chain: SwapChain, address: String, fromAsset: String, toAsset: String, amount: String, interval: String, isAffiliate: Bool) -> URL {
        let isAffiliateParams = isAffiliate
        ? "&affiliate=\(THORChainSwaps.affiliateFeeAddress)&affiliate_bps=\(THORChainSwaps.affiliateFeeRateBp)"
        : .empty
        
        return "\(chain.baseUrl)/quote/swap?from_asset=\(fromAsset)&to_asset=\(toAsset)&amount=\(amount)&destination=\(address)&streaming_interval=\(interval)\(isAffiliateParams)".asUrl
    }
    
    static func fetch1InchSwapQuote(chain: String, source: String, destination: String, amount: String, from: String, slippage: String, referrer: String, fee: Double, isAffiliate: Bool) -> URL {
        
        let isAffiliateParams = isAffiliate
        ? "&referrer=\(referrer)&fee=\(fee)"
        : .empty
        
        return "\(vultisigApiProxy)/1inch/swap/v6.0/\(chain)/swap?src=\(source)&dst=\(destination)&amount=\(amount)&from=\(from)&slippage=\(slippage)&disableEstimate=true&includeGas=true\(isAffiliateParams)".asUrl
    }
    
    static func fetchLiFiQuote(fromChain: String, toChain: String, fromToken: String, toToken: String, fromAmount: String, fromAddress: String) -> URL {
        return "https://li.quest/v1/quote?fromChain=\(fromChain)&toChain=\(toChain)&fromToken=\(fromToken)&toToken=\(toToken)&fromAmount=\(fromAmount)&fromAddress=\(fromAddress)".asUrl
    }
    
    static func fetchTokens(chain: Int) -> String {
        return "\(vultisigApiProxy)/1inch/swap/v6.0/\(chain)/tokens"
    }
    
    static func fetch1InchsTokensBalance(chain: String, address: String) -> String {
        return "\(vultisigApiProxy)/1inch/balance/v1.2/\(chain)/balances/\(address)"
    }
    
    static func fetch1InchsTokensInfo(chain: String, addresses: [String]) -> String {
        let addresses = addresses.joined(separator: ",")
        return "\(vultisigApiProxy)/1inch/token/v1.2/\(chain)/custom?addresses=\(addresses)"
    }
    
    static func fetchCoinPaprikaQuotes(_ quotes: String) -> String {
        "https://api.coinpaprika.com/v1/tickers?quotes=\(quotes)"
    }
    
    static let avalancheServiceRpcService = "https://avalanche-c-chain-rpc.publicnode.com"
    
    static let bscServiceRpcService = "https://bsc-rpc.publicnode.com"
    
    static let baseServiceRpcService = "https://base-rpc.publicnode.com"
    
    static let arbitrumOneServiceRpcService = "https://arbitrum-one-rpc.publicnode.com"
    
    static let polygonServiceRpcService = "https://polygon-bor-rpc.publicnode.com"
    
    static let optimismServiceRpcService = "https://optimism-rpc.publicnode.com"
    
    static let cronosServiceRpcService = "https://cronos-evm-rpc.publicnode.com"
    
    static let blastServiceRpcService = "https://rpc.ankr.com/blast"
    
    static let zksyncServiceRpcService = "https://mainnet.era.zksync.io"
    
    static let ethServiceRpcService = "https://ethereum-rpc.publicnode.com"
    
    static let solanaServiceRpc = "https://api.mainnet-beta.solana.com"
    
    static let solanaTokenInfoServiceRpc = "https://api.solana.fm/v1/tokens"
    
    static let suiServiceRpc = "https://sui-rpc.publicnode.com"
    
    static let polkadotServiceRpc = "https://polkadot-rpc.publicnode.com"
    
    static let polkadotServiceBalance = "https://polkadot.api.subscan.io/api/v2/scan/search"
    
    static func bitcoinLabelTxHash(_ value: String) -> String {
        "https://mempool.space/tx/\(value)"
    }
    
    static func litecoinLabelTxHash(_ value: String) -> String {
        "https://litecoinspace.org/tx/\(value)"
    }
    
    static func blockchairStats(_ chainName: String) -> URL {
        "\(vultisigApiProxy)/blockchair/\(chainName)/stats".asUrl
    }
    
    static func blockchairBroadcast(_ chainName: String) -> URL {
        "\(vultisigApiProxy)/blockchair/\(chainName)/push/transaction".asUrl
    }
    
    static func blockchairDashboard(_ address: String, _ coinName: String) -> URL {
        "\(vultisigApiProxy)/blockchair/\(coinName)/dashboards/address/\(address)".asUrl
    }
    
    static func ethereumLabelTxHash(_ value: String) -> String {
        "https://etherscan.io/tx/\(value)"
    }
    
    static func fetchCryptoPrices(coin: String, fiat: String) -> String {
        "\(vultisigApiProxy)/coingeicko/api/v3/simple/price?ids=\(coin)&vs_currencies=\(fiat)"
    }
    
    static func fetchTokenPrice(network: String, addresses: [String], fiat: String) -> String {
        let addresses = addresses.joined(separator: ",")
        let url = "\(vultisigApiProxy)/coingeicko/api/v3/simple/token_price/\(network.lowercased())?contract_addresses=\(addresses)&vs_currencies=\(fiat)"
        return url
    }
    
    static func fetchTokensInfo(network: String, addresses: [String]) -> String {
        let addresses = addresses.joined(separator: ",")
        return "\(vultisigApiProxy)/coingeicko/api/v3/onchain/networks/\(network)/tokens/multi/\(addresses)"
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
    
    static func fetchDydxAccountBalance(address: String) -> String{
        "https://dydx-rest.publicnode.com/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchDydxAccountNumber(_ address: String) -> String {
        "https://dydx-rest.publicnode.com/cosmos/auth/v1beta1/accounts/\(address)"
    }
    
    static let broadcastDydxTransaction = "https://dydx-rest.publicnode.com/cosmos/tx/v1beta1/txs"
    
    static func fetchKujiraAccountBalance(address: String) -> String{
        "https://kujira-rest.publicnode.com/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchKujiraAccountNumber(_ address: String) -> String {
        "https://kujira-rest.publicnode.com/cosmos/auth/v1beta1/accounts/\(address)"
    }
    
    static let broadcastKujiraTransaction = "https://kujira-rest.publicnode.com/cosmos/tx/v1beta1/txs"
    
    static func getSwapProgressURL(txid: String) -> String {
        return "https://track.ninerealms.com/\(txid.stripHexPrefix())"
    }
    
    static func getMayaSwapTracker(txid: String) -> String {
        return "https://www.mayascan.org/tx/\(txid.stripHexPrefix())"
    }
    
    static func getExplorerURL(chainTicker: String, txid: String) -> String {
        switch chainTicker {
        case "BTC":
            return "https://blockchair.com/bitcoin/transaction/\(txid)"
        case "BCH":
            return "https://blockchair.com/bitcoin-cash/transaction/\(txid)"
        case "LTC":
            return "https://blockchair.com/litecoin/transaction/\(txid)"
        case "DOGE":
            return "https://blockchair.com/dogecoin/transaction/\(txid)"
        case "DASH":
            return "https://blockchair.com/dash/transaction/\(txid)"
        case "RUNE":
            return "https://runescan.io/tx/\(txid.stripHexPrefix())"
        case "SOL":
            return "https://explorer.solana.com/tx/\(txid)"
        case "ETH":
            return "https://etherscan.io/tx/\(txid)"
        case "UATOM":
            return "https://www.mintscan.io/cosmos/tx/\(txid)"
        case "ADYDX":
            return "https://www.mintscan.io/dydx/tx/\(txid)"
        case "UKUJI":
            return "https://finder.kujira.network/kaiyo-1/tx/\(txid)"
        case "AVAX":
            return "https://snowtrace.io/tx/\(txid)"
        case "BNB":
            return "https://bscscan.com/tx/\(txid)"
        case "CACAO":
            return "https://www.mayascan.org/tx/\(txid)"
        case "ARB":
            return "https://arbiscan.io/tx/\(txid)"
        case "BASE":
            return "https://basescan.org/tx/\(txid)"
        case "OP":
            return "https://optimistic.etherscan.io/tx/\(txid)"
        case "MATIC":
            return "https://polygonscan.com/tx/\(txid)"
        case "BLAST":
            return "https://blastscan.io/tx/\(txid)"
        case "CRO":
            return "https://cronoscan.com/tx/\(txid)"
        case "SUI":
            return "https://suiscan.xyz/mainnet/tx/\(txid)"
        case "DOT":
            return "https://polkadot.subscan.io/extrinsic/\(txid)"
        case "ZK":
            return "https://explorer.zksync.io/tx/\(txid)"
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
        case "DASH":
            return "https://blockchair.com/dash/address/\(address)"
        case "RUNE":
            return "https://runescan.io/address/\(address)"
        case "SOL":
            return "https://explorer.solana.com/address/\(address)"
        case "ETH":
            return "https://etherscan.io/address/\(address)"
        case "UATOM":
            return "https://www.mintscan.io/cosmos/address/\(address)"
        case "ADYDX":
            return "https://www.mintscan.io/dydx/address/\(address)"
        case "UKUJI":
            return "https://finder.kujira.network/kaiyo-1/address/\(address)"
        case "AVAX":
            return "https://snowtrace.io/address/\(address)"
        case "BNB":
            return "https://bscscan.com/address/\(address)"
        case "CACAO":
            return "https://www.mayascan.org/address/\(address)"
        case "ARB":
            return "https://arbiscan.io/address/\(address)"
        case "BASE":
            return "https://basescan.org/address/\(address)"
        case "OP":
            return "https://optimistic.etherscan.io/address/\(address)"
        case "MATIC":
            return "https://polygonscan.com/address/\(address)"
        case "BLAST":
            return "https://blastscan.io/address/\(address)"
        case "CRO":
            return "https://cronoscan.com/address/\(address)"
        case "SUI":
            return "https://suiscan.xyz/mainnet/address/\(address)"
        case "DOT":
            return "https://polkadot.subscan.io/account/\(address)"
        case "ZK":
            return "https://explorer.zksync.io/address/\(address)"
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
        case .dydx:
            return "https://www.mintscan.io/dydx/address/\(address)"
        case .kujira:
            return "https://finder.kujira.network/kaiyo-1/address/\(address)"
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
        case .dash:
            return "https://blockchair.com/dash/address/\(address)"
        case .mayaChain:
            return "https://www.mayascan.org/address/\(address)"
        case .arbitrum:
            return "https://arbiscan.io/address/\(address)"
        case .base:
            return "https://basescan.org/address/\(address)" // Hypothetical URL
        case .optimism:
            return "https://optimistic.etherscan.io/address/\(address)"
        case .polygon:
            return "https://polygonscan.com/address/\(address)"
        case .blast:
            return "https://blastscan.io/address/\(address)"
        case .cronosChain:
            return "https://cronoscan.com/address/\(address)"
        case .sui:
            return "https://suiscan.xyz/mainnet/address/\(address)"
        case .polkadot:
            return "https://polkadot.subscan.io/account/\(address)"
        case .zksync:
            return "https://explorer.zksync.io/address/\(address)"
        case .none:
            return nil
        }
    }
    
}

fileprivate extension String {
    
    var asUrl: URL {
        return URL(string: self)!
    }
}
