//
//  Endpoint.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-05.
//

import Foundation

class Endpoint {
    
    // MARK: - Enums
    
    enum SwapChain {
        case thorchain
        case maya
        
        var baseUrl: String {
            switch self {
            case .thorchain:
                return "\(Endpoint.thorNodeBaseUrl)/thorchain"
            case .maya:
                return "\(mayaNodeBaseUrl)/mayachain"
            }
        }
    }
    
    // MARK: - Base URLs
    
    // Vultisig APIs
    static let vultisigApiProxy = "https://api.vultisig.com"
    static let vultisigRelay = "https://api.vultisig.com/router"
    
    // THORChain and Maya
    static let thorNodeBaseUrl = "https://thornode.ninerealms.com"
    static let rpcNineRealmsBaseUrl = "https://rpc.ninerealms.com"
    static let mayaNodeBaseUrl = "https://mayanode.mayachain.info"
    
    // Cosmos Ecosystem
    static let cosmosPublicNodeBaseUrl = "https://cosmos-rest.publicnode.com"
    static let osmosisPublicNodeBaseUrl = "https://osmosis-rest.publicnode.com"
    static let terraPublicNodeBaseUrl = "https://terra-lcd.publicnode.com"
    static let terraClassicPublicNodeBaseUrl = "https://terra-classic-lcd.publicnode.com"
    static let noblePublicNodeBaseUrl = "https://noble-api.polkachu.com"
    static let dydxPublicNodeBaseUrl = "https://dydx-rest.publicnode.com"
    static let kujiraPublicNodeBaseUrl = "https://kujira-rest.publicnode.com"
    static let akashPublicNodeBaseUrl = "https://akash-rest.publicnode.com"
    
    // Other Chains
    static let tronRpcBaseUrl = "https://tron-rpc.publicnode.com"
    static let tronGridBaseUrl = "https://api.trongrid.io"
    
    // MARK: - Vultisig Endpoints
    
    static let supportDocumentLink = "https://docs.vultisig.com/user-actions/creating-a-vault"
    static let FastVaultBackupVerification = vultisigApiProxy + "/vault/verify/"
    
    // MARK: - App Update Endpoints
    
    static let updateVersionCheck = "https://api.github.com/repos/vultisig/vultisig-ios/releases"
    static let githubMacUpdateBase = "https://github.com/vultisig/vultisig-ios/releases/tag/"
    static let githubMacDownloadBase = "https://github.com/vultisig/vultisig-ios/releases/download/"
    
    // MARK: - THORChain Endpoints
    
    // Transaction and Network
    static let broadcastTransactionThorchainNineRealms = "\(thorNodeBaseUrl)/cosmos/tx/v1beta1/txs"
    static let fetchThorchainNetworkInfoNineRealms = "\(thorNodeBaseUrl)/thorchain/network"
    static let thorchainNetworkInfo = "\(rpcNineRealmsBaseUrl)/status".asUrl
    static let fetchThorchainInboundAddressesNineRealms = "\(thorNodeBaseUrl)/thorchain/inbound_addresses"
    
    // Account
    static func fetchAccountNumberThorchainNineRealms(_ address: String) -> String {
        "\(thorNodeBaseUrl)/auth/accounts/\(address)"
    }
    
    static func fetchAccountBalanceThorchainNineRealms(address: String) -> String {
        "\(thorNodeBaseUrl)/cosmos/bank/v1beta1/balances/\(address)"
    }
    
    // TCY-specific endpoints
    static func fetchTCYStaker(address: String) -> String {
        "\(thorNodeBaseUrl)/thorchain/tcy_staker/\(address)"
    }
    
    static func fetchTCYStakers() -> String {
        "\(thorNodeBaseUrl)/thorchain/tcy_stakers"
    }
    
    static func fetchTCYClaimers() -> String {
        "\(thorNodeBaseUrl)/thorchain/tcy_claimers"
    }
    
    static func fetchTCYClaimer(address: String) -> String {
        "\(thorNodeBaseUrl)/thorchain/tcy_claimer/\(address)"
    }
    
    // Fetch pool info for any THORChain asset
    static func fetchPoolInfo(asset: String) -> String {
        "\(thorNodeBaseUrl)/thorchain/pool/\(asset)"
    }
    
    // MARK: - Maya Chain Endpoints
    
    static let broadcastTransactionMayachain = "\(mayaNodeBaseUrl)/cosmos/tx/v1beta1/txs"
    static let depositAssetsMaya = "\(mayaNodeBaseUrl)/mayachain/pools"
    
    static func fetchAccountNumberMayachain(_ address: String) -> String {
        "\(mayaNodeBaseUrl)/auth/accounts/\(address)"
    }
    
    static func fetchAccountBalanceMayachain(address: String) -> String {
        "\(mayaNodeBaseUrl)/cosmos/bank/v1beta1/balances/\(address)"
    }
    
    // MARK: - Swap Endpoints
    
    static func fetchSwapQuoteThorchain(chain: SwapChain, address: String, fromAsset: String, toAsset: String, amount: String, interval: String, isAffiliate: Bool) -> URL {
        let isAffiliateParams = isAffiliate
        ? "&affiliate=\(THORChainSwaps.affiliateFeeAddress)&affiliate_bps=\(THORChainSwaps.affiliateFeeRateBp)"
        : ""
        
        return "\(chain.baseUrl)/quote/swap?from_asset=\(fromAsset)&to_asset=\(toAsset)&amount=\(amount)&destination=\(address)&streaming_interval=\(interval)\(isAffiliateParams)".asUrl
    }
    
    static func fetch1InchSwapQuote(chain: String, source: String, destination: String, amount: String, from: String, slippage: String, referrer: String, fee: Double, isAffiliate: Bool) -> URL {
        
        let isAffiliateParams = isAffiliate
        ? "&referrer=\(referrer)&fee=\(fee)"
        : ""
        
        return "\(vultisigApiProxy)/1inch/swap/v6.0/\(chain)/swap?src=\(source)&dst=\(destination)&amount=\(amount)&from=\(from)&slippage=\(slippage)&disableEstimate=true&includeGas=true\(isAffiliateParams)".asUrl
    }
    
    // MARK: - Cross-Chain and DEX Endpoints
    
    static func fetchLiFiQuote(fromChain: String, toChain: String, fromToken: String, toAddress: String, toToken: String, fromAmount: String, fromAddress: String, integrator: String?, fee: String?) -> URL {
        var url = "https://li.quest/v1/quote?fromChain=\(fromChain)&toChain=\(toChain)&fromToken=\(fromToken)&toToken=\(toToken)&fromAddress=\(fromAddress)&toAddress=\(toAddress)&fromAmount=\(fromAmount)"
        
        if let integrator, let fee {
            return (url + "&integrator=\(integrator)&fee=\(fee)").asUrl
        }
        
        return url.asUrl
    }
    
    static func fetchTokens(chain: Int) -> String {
        return "\(vultisigApiProxy)/1inch/swap/v6.0/\(chain)/tokens"
    }
    
    // MARK: - Token Info Endpoints
    
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
    
    // MARK: - RPC Services
    
    // Vultisig-proxied RPC endpoints
    static let avalancheServiceRpcService = "https://api.vultisig.com/avax/"
    static let bscServiceRpcService = "https://api.vultisig.com/bsc/"
    static let baseServiceRpcService = "https://api.vultisig.com/base/"
    static let arbitrumOneServiceRpcService = "https://api.vultisig.com/arb/"
    static let polygonServiceRpcService = "https://api.vultisig.com/polygon/"
    static let blastServiceRpcService = "https://api.vultisig.com/blast/"
    static let cronosServiceRpcService = "https://api.vultisig.com/cronos/"
    static let ethServiceRpcService = "https://api.vultisig.com/eth/"
    static let solanaServiceRpc = "https://api.vultisig.com/solana/"
    
    // Third-party RPC endpoints
    static let solanaTokenInfoServiceRpc = "https://api.solana.fm/v1/tokens"
    static let suiServiceRpc = "https://sui-rpc.publicnode.com"
    static let polkadotServiceRpc = "https://polkadot-rpc.publicnode.com"
    static let rippleServiceRpc = "https://xrplcluster.com"
    static let cronosServiceRpcRaw = "https://cronos-evm-rpc.publicnode.com"
    static let zksyncServiceRpcService = "https://api.vultisig.com/zksync/"
    
    static func solanaTokenInfoServiceRpc2(tokenAddress: String) -> String {
        "https://tokens.jup.ag/token/\(tokenAddress)"
    }
    
    static func solanaTokenInfoList() -> String {
        "https://tokens.jup.ag/tokens?tags=verified"
    }
    
    // DEX Quote Endpoints
    static func fetchJupiterSwapQuote(inputMint: String, outputMint: String, amount: String, slippageBps: String) -> String {
        "https://quote-api.jup.ag/v6/quote?inputMint=\(inputMint)&outputMint=\(outputMint)&amount=\(amount)&slippageBps=\(slippageBps)"
    }
    
    // For backward compatibility with existing code
    static func solanaTokenQuote(inputMint: String, outputMint: String, amount: String, slippageBps: String) -> String {
        return fetchJupiterSwapQuote(inputMint: inputMint, outputMint: outputMint, amount: amount, slippageBps: slippageBps)
    }
    
    static func suiTokenQuote() -> String {
        "https://api-sui.cetus.zone/v2/sui/swap/count"
    }
    
    static let optimismServiceRpcService = "https://api.vultisig.com/opt/"
    static let polkadotServiceBalance = "https://polkadot.api.subscan.io/api/v2/scan/search"
    
    static let tonServiceRpc = "https://api.vultisig.com/ton/v2/jsonRPC"
    
    static func fetchTonBalance(address: String) -> String {
        return "https://api.vultisig.com/ton/v3/addressInformation?address=\(address)&use_v2=false";
    }
    
    static func fetchMemoInfo(hash: String) -> URL {
        return "https://api.etherface.io/v1/signatures/hash/all/\(hash)/1".asUrl
    }
    
    static func fetchExtendedAddressInformation(address: String) -> String {
        return "https://api.vultisig.com/ton/v2/getExtendedAddressInformation?address=\(address)";
    }
    
    static func broadcastTonTransaction() -> String {
        return "https://api.vultisig.com/ton/v2/sendBocReturnHash";
    }
    
    // MARK: - Naming Services
    
    static func resolveTNS(name: String) -> URL {
        "https://midgard.ninerealms.com/v2/thorname/lookup/\(name)".asUrl
    }
    
    // MARK: - Transaction Explorer URLs
    
    // Individual Chain Explorer URLs
    static func bitcoinLabelTxHash(_ value: String) -> String {
        "https://mempool.space/tx/\(value)"
    }
    
    static func litecoinLabelTxHash(_ value: String) -> String {
        "https://litecoinspace.org/tx/\(value)"
    }
    
    static func rippleLabelTxHash(_ value: String) -> String {
        "https://xrpscan.com/tx/\(value)"
    }
    
    static func bscLabelTxHash(_ value: String) -> String {
        "https://bscscan.com/tx/\(value)"
    }
    
    static func ethereumLabelTxHash(_ value: String) -> String {
        "https://etherscan.io/tx/\(value)"
    }
    
    static func blockchairStats(_ chainName: String) -> URL {
        "\(vultisigApiProxy)/blockchair/\(chainName)/stats".asUrl
    }
    
    static func blockchairBroadcast(_ chainName: String) -> URL {
        "\(vultisigApiProxy)/blockchair/\(chainName)/push/transaction".asUrl
    }
    
    static func blockchairDashboard(_ address: String, _ coinName: String) -> URL {
        // ?state=latest
        "\(vultisigApiProxy)/blockchair/\(coinName)/dashboards/address/\(address)?state=latest".asUrl
    }
    
    // MARK: - Price APIs
    
    static func fetchCryptoPrices(ids: String, currencies: String) -> URL {
        "\(vultisigApiProxy)/coingeicko/api/v3/simple/price?ids=\(ids)&vs_currencies=\(currencies)".asUrl
    }
    
    // MARK: - Token Price Endpoints
    
    static func fetchLifiTokenPrice(network: String, address: String) -> URL {
        let url = "https://li.quest/v1/token?chain=\(network.lowercased())&token=\(address)"
        return url.asUrl
    }
    
    static func fetchTokenPrice(network: String, addresses: [String], currencies: String) -> URL {
        let addresses = addresses.joined(separator: ",")
        let url = "\(vultisigApiProxy)/coingeicko/api/v3/simple/token_price/\(network.lowercased())?contract_addresses=\(addresses)&vs_currencies=\(currencies)"
        return url.asUrl
    }
    
    static func fetchTokensInfo(network: String, addresses: [String]) -> String {
        let addresses = addresses.joined(separator: ",")
        return "\(vultisigApiProxy)/coingeicko/api/v3/onchain/networks/\(network)/tokens/multi/\(addresses)"
    }
    
    // MARK: - Transaction History Endpoints
    
    // Chain-specific Transaction History APIs
    static func fetchBitcoinTransactions(_ userAddress: String) -> String {
        "https://mempool.space/api/address/\(userAddress)/txs"
    }
    
    static func fetchLitecoinTransactions(_ userAddress: String) -> String {
        "https://litecoinspace.org/api/address/\(userAddress)/txs"
    }
    
    
    // MARK: - Cosmos Ecosystem Endpoints
    
    // Osmosis
    static func fetchOsmosisAccountBalance(address: String) -> String{
        "\(osmosisPublicNodeBaseUrl)/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchOsmosisAccountNumber(_ address: String) -> String {
        "\(osmosisPublicNodeBaseUrl)/cosmos/auth/v1beta1/accounts/\(address)"
    }
    
    static let broadcastOsmosisTransaction = "\(osmosisPublicNodeBaseUrl)/cosmos/tx/v1beta1/txs"
    
    static func fetchOsmosisWasmTokenBalance(contractAddress: String, base64Payload: String) -> String {
        "\(osmosisPublicNodeBaseUrl)/cosmwasm/wasm/v1/contract/\(contractAddress)/smart/\(base64Payload)"
    }
    
    static func fetchOsmosisIbcDenomTraces(hash: String) -> String{
        "\(osmosisPublicNodeBaseUrl)/ibc/apps/transfer/v1/denom_traces/\(hash)"
    }
    
    static func fetchOsmosisLatestBlock() -> String{
        "\(osmosisPublicNodeBaseUrl)/cosmos/base/tendermint/v1beta1/blocks/latest"
    }
    
    // Akash
    static func fetchAkashAccountBalance(address: String) -> String{
        "\(akashPublicNodeBaseUrl)/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchAkashAccountNumber(_ address: String) -> String {
        "\(akashPublicNodeBaseUrl)/cosmos/auth/v1beta1/accounts/\(address)"
    }
    
    static let broadcastAkashTransaction = "\(akashPublicNodeBaseUrl)/cosmos/tx/v1beta1/txs"
    
    // Noble
    static func fetchNobleAccountBalance(address: String) -> String{
        "\(noblePublicNodeBaseUrl)/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchNobleAccountNumber(_ address: String) -> String {
        "\(noblePublicNodeBaseUrl)/cosmos/auth/v1beta1/accounts/\(address)"
    }
    
    static let broadcastNobleTransaction = "\(noblePublicNodeBaseUrl)/cosmos/tx/v1beta1/txs"
    
    // Cosmos
    static func fetchCosmosAccountBalance(address: String) -> String{
        "\(cosmosPublicNodeBaseUrl)/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchCosmosAccountNumber(_ address: String) -> String {
        "\(cosmosPublicNodeBaseUrl)/cosmos/auth/v1beta1/accounts/\(address)"
    }
    
    static let broadcastCosmosTransaction = "\(cosmosPublicNodeBaseUrl)/cosmos/tx/v1beta1/txs"
    
    static func fetchCosmosWasmTokenBalance(contractAddress: String, base64Payload: String) -> String {
        "\(cosmosPublicNodeBaseUrl)/cosmwasm/wasm/v1/contract/\(contractAddress)/smart/\(base64Payload)"
    }
    
    static func fetchCosmosIbcDenomTraces(hash: String) -> String{
        "\(cosmosPublicNodeBaseUrl)/ibc/apps/transfer/v1/denom_traces/\(hash)"
    }
    
    static func fetchCosmosLatestBlock() -> String{
        "\(cosmosPublicNodeBaseUrl)/cosmos/base/tendermint/v1beta1/blocks/latest"
    }
    
    // Terra
    static func fetchTerraAccountBalance(address: String) -> String{
        "\(terraPublicNodeBaseUrl)/cosmos/bank/v1beta1/spendable_balances/\(address)"
    }
    static func fetchTerraAccountNumber(_ address: String) -> String {
        "\(terraPublicNodeBaseUrl)/cosmos/auth/v1beta1/accounts/\(address)"
    }
    
    static let broadcastTerraTransaction = "\(terraPublicNodeBaseUrl)/cosmos/tx/v1beta1/txs"
    
    static func fetchTerraIbcDenomTraces(hash: String) -> String{
        "\(terraPublicNodeBaseUrl)/ibc/apps/transfer/v1/denom_traces/\(hash)"
    }
    
    static func fetchTerraWasmTokenBalance(contractAddress: String, base64Payload: String) -> String {
        "\(terraPublicNodeBaseUrl)/cosmwasm/wasm/v1/contract/\(contractAddress)/smart/\(base64Payload)"
    }
    
    static func fetchTerraLatestBlock() -> String{
        "\(terraPublicNodeBaseUrl)/cosmos/base/tendermint/v1beta1/blocks/latest"
    }
    
    // Terra Classic
    static func fetchTerraClassicAccountBalance(address: String) -> String{
        "\(terraClassicPublicNodeBaseUrl)/cosmos/bank/v1beta1/spendable_balances/\(address)"
    }
    static func fetchTerraClassicAccountNumber(_ address: String) -> String {
        "\(terraClassicPublicNodeBaseUrl)/cosmos/auth/v1beta1/accounts/\(address)"
    }
    
    static let broadcastTerraClassicTransaction = "\(terraClassicPublicNodeBaseUrl)/cosmos/tx/v1beta1/txs"
    
    static func fetchTerraClassicIbcDenomTraces(hash: String) -> String{
        "\(terraClassicPublicNodeBaseUrl)/ibc/apps/transfer/v1/denom_traces/\(hash)"
    }
    
    static func fetchTerraClassicWasmTokenBalance(contractAddress: String, base64Payload: String) -> String {
        "\(terraClassicPublicNodeBaseUrl)/cosmwasm/wasm/v1/contract/\(contractAddress)/smart/\(base64Payload)"
    }
    
    static func fetchTerraClassicLatestBlock() -> String{
        "\(terraClassicPublicNodeBaseUrl)/cosmos/base/tendermint/v1beta1/blocks/latest"
    }
    
    // dYdX
    static func fetchDydxAccountBalance(address: String) -> String{
        "\(dydxPublicNodeBaseUrl)/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchDydxAccountNumber(_ address: String) -> String {
        "\(dydxPublicNodeBaseUrl)/cosmos/auth/v1beta1/accounts/\(address)"
    }
    
    static let broadcastDydxTransaction = "\(dydxPublicNodeBaseUrl)/cosmos/tx/v1beta1/txs"
    
    // Kujira
    static func fetchKujiraAccountBalance(address: String) -> String{
        "\(kujiraPublicNodeBaseUrl)/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchKujiraAccountNumber(_ address: String) -> String {
        "\(kujiraPublicNodeBaseUrl)/cosmos/auth/v1beta1/accounts/\(address)"
    }
    
    static let broadcastKujiraTransaction = "\(kujiraPublicNodeBaseUrl)/cosmos/tx/v1beta1/txs"
    
    static func fetchKujiraWasmTokenBalance(contractAddress: String, base64Payload: String) -> String {
        "\(kujiraPublicNodeBaseUrl)/cosmwasm/wasm/v1/contract/\(contractAddress)/smart/\(base64Payload)"
    }
    
    static func fetchKujiraIbcDenomTraces(hash: String) -> String{
        "\(kujiraPublicNodeBaseUrl)/ibc/apps/transfer/v1/denom_traces/\(hash)"
    }
    
    static func fetchKujiraLatestBlock() -> String{
        "\(kujiraPublicNodeBaseUrl)/cosmos/base/tendermint/v1beta1/blocks/latest"
    }
    
    // MARK: - Swap Tracking URLs
    
    static func getSwapProgressURL(txid: String) -> String {
        return "https://thorchain.net/tx/\(txid.stripHexPrefix())"
    }
    
    static func getMayaSwapTracker(txid: String) -> String {
        return "https://www.xscanner.org/tx/\(txid.stripHexPrefix())"
    }
    
    // MARK: - Tron Network Endpoints
    
    static let tronServiceRpc = tronRpcBaseUrl
    
    static let broadcastTransactionTron = "\(tronRpcBaseUrl)/wallet/broadcasttransaction"
    
    static let fetchBlockNowInfoTron = "\(tronRpcBaseUrl)/wallet/getnowblock"
    
    static func fetchAccountInfoTron() -> String {
        "\(tronRpcBaseUrl)/wallet/getaccount"
    }
    
    static func triggerConstantContractTron() -> String {
        "\(tronGridBaseUrl)/wallet/triggerconstantcontract"
    }
    
    static func triggerSolidityConstantContractTron() -> String {
        "\(tronGridBaseUrl)/walletsolidity/triggerconstantcontract"
    }
    
    static let tronEvmServiceRpc = "\(tronGridBaseUrl)/jsonrpc"
    
    // MARK: - Explorer URLs
    
    static func getExplorerURL(chainTicker: String, txid: String) -> String {
        switch chainTicker {
        case "BTC":
            return "https://mempool.space/tx/\(txid)"
        case "BCH":
            return "https://blockchair.com/bitcoin-cash/transaction/\(txid)"
        case "LTC":
            return "https://blockchair.com/litecoin/transaction/\(txid)"
        case "DOGE":
            return "https://blockchair.com/dogecoin/transaction/\(txid)"
        case "DASH":
            return "https://blockchair.com/dash/transaction/\(txid)"
        case "RUNE":
            return "https://thorchain.net/tx/\(txid.stripHexPrefix())"
        case "SOL":
            return "https://solscan.io/tx/\(txid)"
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
        case "TON":
            return "https://tonviewer.com/transaction/\(txid)"
        case "UOSMO":
            return "https://www.mintscan.io/osmosis/tx/\(txid)"
        case "ULUNA":
            return "https://www.mintscan.io/terra/tx/\(txid)"
        case "ULUNC":
            return "https://finder.terra.money/classic/tx/\(txid)"
        case "USDC":
            return "https://www.mintscan.io/noble/tx/\(txid)"
        case "XRP":
            return "https://xrpscan.com/tx/\(txid)"
        case "UAKT":
            return "https://www.mintscan.io/akash/tx/\(txid)"
        case "TRX":
            return "https://tronscan.org/#/transaction/\(txid)"
        default:
            return ""
        }
    }
    
    static func getExplorerByAddressURL(chainTicker:String, address:String) -> String? {
        switch chainTicker {
        case "BTC":
            return "https://mempool.space/address/\(address)"
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
            return "https://solscan.io/account/\(address)"
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
        case "TON":
            return "https://tonviewer.com/\(address)"
        case "UOSMO":
            return "https://www.mintscan.io/osmosis/address/\(address)"
        case "ULUNA":
            return "https://www.mintscan.io/terra/address/\(address)"
        case "ULUNC":
            return "https://finder.terra.money/classic/address/\(address)"
        case "USDC":
            return "https://www.mintscan.io/noble/address/\(address)"
        case "XRP":
            return "https://xrpscan.com/account/\(address)"
        case "UAKT":
            return "https://www.mintscan.io/akash/address/\(address)"
        case "TRX":
            return "https://tronscan.org/#/address/\(address)"
        default:
            return nil
        }
    }
    
    static func getExplorerByAddressURLByGroup(chain: Chain?, address: String) -> String? {
        switch chain {
        case .thorChain:
            return "https://thorchain.net/address/\(address)"
        case .solana:
            return "https://solscan.io/account/\(address)"
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
            return "https://mempool.space/address/\(address)"
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
        case .polygon, .polygonV2:
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
        case .ton:
            return "https://tonviewer.com/\(address)"
        case .osmosis:
            return "https://www.mintscan.io/osmosis/address/\(address)"
        case .terra:
            return "https://www.mintscan.io/terra/address/\(address)"
        case .terraClassic:
            return "https://finder.terra.money/classic/address/\(address)"
        case .noble:
            return "https://www.mintscan.io/noble/address/\(address)"
        case .ripple:
            return "https://xrpscan.com/account/\(address)"
        case .akash:
            return "https://www.mintscan.io/akash/address/\(address)"
        case .tron:
            return "https://tronscan.org/#/address/\(address)"
        case .none:
            return nil
        }
    }
    
}

// MARK: - Helper Extensions

fileprivate extension String {
    
    var asUrl: URL {
        return URL(string: self)!
    }
}
