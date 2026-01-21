//
//  Endpoint.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-05.
//

import Foundation

class Endpoint {

    private static func encodePathComponent(_ value: String) -> String {
        let disallowSlash = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        return value.addingPercentEncoding(withAllowedCharacters: disallowSlash) ?? value
    }

    enum SwapChain {
        case thorchain
        case thorchainStagenet
        case maya

        var baseUrl: String {
            switch self {
            case .thorchain:
                return "https://thornode.ninerealms.com/thorchain"
            case .thorchainStagenet:
                return "https://chainnet-thornode.thorchain.network/thorchain"
            case .maya:
                return "https://mayanode.mayachain.info/mayachain"
            }
        }
    }

    static let vultisigApiProxy = "https://api.vultisig.com"
    static let supportDocumentLink = "https://docs.vultisig.com/vultisig-app-actions/managing-your-vault/vault-backup#recovering-a-lost-device"
    static let vultisigRelay = "https://api.vultisig.com/router"
    static let broadcastTransactionThorchainNineRealms = "https://thornode.ninerealms.com/cosmos/tx/v1beta1/txs"
    static let broadcastTransactionMayachain = "https://mayanode.mayachain.info/cosmos/tx/v1beta1/txs"

    static let updateVersionCheck = "https://api.github.com/repos/vultisig/vultisig-ios/releases"
    static let githubMacUpdateBase = "https://github.com/vultisig/vultisig-ios/releases/tag/"
    static let githubMacDownloadBase = "https://github.com/vultisig/vultisig-ios/releases/download/"

    // Security/Fraud Detection Services - Proxied through Vultisig API
    static let blockaidApiBase = "\(vultisigApiProxy)/blockaid/v0"

    // OFFICIAL BLOCKAID API ENDPOINTS (Working ✅)

    // EVM Endpoints
    static func blockaidEVMJSONRPCScan() -> String {
        return "\(blockaidApiBase)/evm/json-rpc/scan"
    }

    static func blockaidEVMTransactionScan() -> String {
        return "\(blockaidApiBase)/evm/transaction/scan"
    }

    static func blockaidEVMTransactionRawScan() -> String {
        return "\(blockaidApiBase)/evm/transaction/raw/scan"
    }

    static func blockaidEVMAddressScan() -> String {
        return "\(blockaidApiBase)/evm/address/scan"
    }

    static func blockaidEVMUserOperationScan() -> String {
        return "\(blockaidApiBase)/evm/user-operation/scan"
    }

    // Site Scanning
    static func blockaidSiteScan() -> String {
        return "\(blockaidApiBase)/site/scan"
    }

    // Token Scanning
    static func blockaidTokenScan() -> String {
        return "\(blockaidApiBase)/token/scan"
    }

    // Multi-Chain Support
    static func blockaidBitcoinTransactionRaw() -> String {
        return "\(blockaidApiBase)/bitcoin/transaction/raw"
    }

    static func blockaidSolanaAddressScan() -> String {
        return "\(blockaidApiBase)/solana/address/scan"
    }

    static func blockaidSolanaMessageScan() -> String {
        return "\(blockaidApiBase)/solana/message/scan"
    }

    static func blockaidStarknetTransactionScan() -> String {
        return "\(blockaidApiBase)/starknet/transaction/scan"
    }

    static func blockaidStellarAddressScan() -> String {
        return "\(blockaidApiBase)/stellar/address/scan"
    }

    static func blockaidStellarTransactionScan() -> String {
        return "\(blockaidApiBase)/stellar/transaction/scan"
    }

    static func blockaidSuiAddressScan() -> String {
        return "\(blockaidApiBase)/sui/address/scan"
    }

    static func blockaidSuiTransactionScan() -> String {
        return "\(blockaidApiBase)/sui/transaction/scan"
    }

    // Chain-Agnostic
    static func blockaidChainAgnosticTransaction() -> String {
        return "\(blockaidApiBase)/chain-agnostic/transaction"
    }

    // Enterprise Features
    static func blockaidExchangeProtectionWithdrawal() -> String {
        return "\(blockaidApiBase)/exchange-protection/withdrawal"
    }

    // Legacy endpoint methods (for backward compatibility)
    static func blockaidAddressScan() -> String {
        return blockaidEVMAddressScan()
    }

    static let FastVaultBackupVerification = vultisigApiProxy + "/vault/verify/"

    static func fetchAccountNumberThorchainNineRealms(_ address: String) -> String {
        "https://thornode.ninerealms.com/auth/accounts/\(address)"
    }

    static let fetchThorchainNetworkInfoNineRealms = "https://thornode.ninerealms.com/thorchain/network"

    static func fetchThorchainDenomMetadata(denom: String) -> String {
        "https://thornode.ninerealms.com/cosmos/bank/v1beta1/denoms_metadata/\(encodePathComponent(denom))"
    }

    static func fetchThorchainAllDenomMetadata() -> String {
        "https://thornode.ninerealms.com/cosmos/bank/v1beta1/denoms_metadata?pagination.limit=1000"
    }
    static let thorchainNetworkInfo = "https://rpc.ninerealms.com/status".asUrl

    static let fetchThorchainInboundAddressesNineRealms = "https://thornode.ninerealms.com/thorchain/inbound_addresses"

    // Stagenet endpoints
    static func fetchAccountNumberThorchainStagenet(_ address: String) -> String {
        "https://chainnet-thornode.thorchain.network/auth/accounts/\(address)"
    }

    static let fetchThorchainStagenetNetworkInfoNineRealms = "https://chainnet-thornode.thorchain.network/thorchain/network"

    static func fetchThorchainStagenetDenomMetadata(denom: String) -> String {
        "https://chainnet-thornode.thorchain.network/cosmos/bank/v1beta1/denoms_metadata/\(encodePathComponent(denom))"
    }

    static func fetchThorchainStagenetAllDenomMetadata() -> String {
        "https://chainnet-thornode.thorchain.network/cosmos/bank/v1beta1/denoms_metadata?pagination.limit=1000"
    }

    static let thorchainStagenetNetworkInfo = "https://chainnet-rpc.thorchain.network/status".asUrl

    static let fetchThorchainStagenetInboundAddressesNineRealms = "https://chainnet-thornode.thorchain.network/thorchain/inbound_addresses"

    static let broadcastTransactionThorchainStagenet = "https://chainnet-thornode.thorchain.network/cosmos/tx/v1beta1/txs"

    static func fetchAccountNumberMayachain(_ address: String) -> String {
        "https://mayanode.mayachain.info/auth/accounts/\(address)"
    }
    static func fetchAccountBalanceThorchainNineRealms(address: String) -> String {
        "https://thornode.ninerealms.com/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchAccountBalanceThorchainStagenet(address: String) -> String {
        "https://chainnet-thornode.thorchain.network/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchAccountBalanceMayachain(address: String) -> String {
        "https://mayanode.mayachain.info/cosmos/bank/v1beta1/balances/\(address)"
    }

    // Fetch pool info for any THORChain asset
    static func fetchPoolInfo(asset: String) -> String {
        "https://thornode.ninerealms.com/thorchain/pool/\(asset)"
    }

    static func fetchStagenetPoolInfo(asset: String) -> String {
        "https://chainnet-thornode.thorchain.network/thorchain/pool/\(asset)"
    }

    static func fetchTcyStakedAmount(address: String) -> String {
        "https://thornode.ninerealms.com/thorchain/tcy_staker/\(address)"
    }

    static func fetchTcyAutoCompoundStatus() -> String {
        "https://rpc.ninerealms.com/cosmwasm/wasm/v1/contract/thor1z7ejlk5wk2pxh9nfwjzkkdnrq4p2f5rjcpudltv0gh282dwfz6nq9g2cr0/smart/eyJzdGF0dXMiOnt9fQ=="
    }

    static func fetchTcyAutoCompoundBalance(address: String) -> String {
        // Query user's sTCY balance using cosmos bank API - URL encode the denom
        "https://rpc.ninerealms.com/cosmos/bank/v1beta1/balances/\(address)/by_denom?denom=x%2Fstaking-tcy"
    }

    static func fetchYRunePrice() -> String {
        "https://thornode-mainnet-api.bryanlabs.net/cosmwasm/wasm/v1/contract/thor1mlphkryw5g54yfkrp6xpqzlpv4f8wh6hyw27yyg4z2els8a9gxpqhfhekt/smart/eyJzdGF0dXMiOiB7fX0="
    }

    static func fetchYtcyPrice() -> String {
        "https://thornode-mainnet-api.bryanlabs.net/cosmwasm/wasm/v1/contract/thor1h0hr0rm3dawkedh44hlrmgvya6plsryehcr46yda2vj0wfwgq5xqrs86px/smart/eyJzdGF0dXMiOiB7fX0="
    }

    static func fetchThorchainMergedAssets() -> String {
        "https://api.vultisig.com/ruji/api/graphql"
    }

    static let depositAssetsMaya = "https://mayanode.mayachain.info/mayachain/pools"

    // THORChain LP endpoints
    static func fetchThorchainPoolLiquidityProvider(asset: String, address: String) -> String {
        "https://thornode.ninerealms.com/thorchain/pool/\(asset)/liquidity_provider/\(address)"
    }

    static let fetchThorchainPools = "https://thornode.ninerealms.com/thorchain/pools"

    // THORChain Stagenet LP endpoints
    static func fetchThorchainStagenetPoolLiquidityProvider(asset: String, address: String) -> String {
        "https://chainnet-thornode.thorchain.network/thorchain/pool/\(asset)/liquidity_provider/\(address)"
    }

    static let fetchThorchainStagenetPools = "https://chainnet-thornode.thorchain.network/thorchain/pools"

    static func fetchSwapQuoteThorchain(
        chain: SwapChain,
        address: String,
        fromAsset: String,
        toAsset: String,
        amount: String,
        interval: String,
        referredCode: String,
        vultTierDiscount: Int
    ) -> URL {
        let affiliateParams = buildAffiliateParams(chain: chain, referredCode: referredCode, discountBps: vultTierDiscount)
        return "\(chain.baseUrl)/quote/swap?from_asset=\(fromAsset)&to_asset=\(toAsset)&amount=\(amount)&destination=\(address)&streaming_interval=\(interval)\(affiliateParams)".asUrl
    }

    static func buildAffiliateParams(chain: SwapChain, referredCode: String, discountBps: Int) -> String {
        var affiliateParams: [(affiliate: String, bps: String)] = []

        if (chain == .thorchain || chain == .thorchainStagenet) && !referredCode.isEmpty {
            // THORChain supports nested affiliates
            let affiliateFeeRateBp = bps(for: discountBps, affiliateFeeRate: THORChainSwaps.referredAffiliateFeeRateBp)
            affiliateParams.append((referredCode, THORChainSwaps.referredUserFeeRateBp))
            affiliateParams.append((THORChainSwaps.affiliateFeeAddress, "\(affiliateFeeRateBp)"))
        } else {
            // MayaChain only supports single affiliate
            let affiliateFeeRateBp = bps(for: discountBps, affiliateFeeRate: THORChainSwaps.affiliateFeeRateBp)
            affiliateParams.append((THORChainSwaps.affiliateFeeAddress, "\(affiliateFeeRateBp)"))
        }

        guard !affiliateParams.isEmpty else { return .empty }

        let affiliates = affiliateParams.map(\.affiliate).joined(separator: "/")
        let affiliateBps = affiliateParams.map(\.bps).joined(separator: "/")

        return "&affiliate=\(affiliates)&affiliate_bps=\(affiliateBps)"
    }

    static func bps(for discount: Int, affiliateFeeRate: Int) -> Int {
        max(0, affiliateFeeRate - discount)
    }

    static func fetch1InchSwapQuote(
        chain: String,
        source: String,
        destination: String,
        amount: String,
        from: String,
        slippage: String,
        referrer: String,
        fee: Double,
        isAffiliate: Bool
    ) -> URL {

        let isAffiliateParams = isAffiliate
        ? "&referrer=\(referrer)&fee=\(fee)"
        : "&referrer=\(referrer)&fee=0"

        return "\(vultisigApiProxy)/1inch/swap/v6.1/\(chain)/swap?src=\(source)&dst=\(destination)&amount=\(amount)&from=\(from)&slippage=\(slippage)&includeGas=true&disableEstimate=true\(isAffiliateParams)".asUrl
    }

    static func fetchLiFiQuote(
        fromChain: String,
        toChain: String,
        fromToken: String,
        toAddress: String,
        toToken: String,
        fromAmount: String,
        fromAddress: String,
        integrator: String?,
        fee: String?
    ) -> URL {
        var url = "https://li.quest/v1/quote?fromChain=\(fromChain)&toChain=\(toChain)&fromToken=\(fromToken)&toToken=\(toToken)&fromAmount=\(fromAmount)&fromAddress=\(fromAddress)&toAddress=\(toAddress)"

        if let integrator {
           url = url + "&integrator=\(integrator)"
        }

        if let fee {
            url = url + "&fee=\(fee)"
        }

        return url.asUrl
    }

    static func fetchTokens(chain: Int) -> String {
        return "\(vultisigApiProxy)/1inch/swap/v6.0/\(chain)/tokens"
    }

    static func fetchKyberSwapRoute(chain: String, tokenIn: String, tokenOut: String, amountIn: String, saveGas: Bool, gasInclude: Bool, slippageTolerance: Int, isAffiliate: Bool, sourceIdentifier: String? = nil, referrerAddress: String? = nil) -> URL {
        let baseUrl = "https://aggregator-api.kyberswap.com/\(chain)/api/v1/routes?tokenIn=\(tokenIn)&tokenOut=\(tokenOut)&amountIn=\(amountIn)&saveGas=\(saveGas)&gasInclude=\(gasInclude)&slippageTolerance=\(slippageTolerance)"

        let affiliateParams = isAffiliate && sourceIdentifier != nil && referrerAddress != nil
        ? "&source=\(sourceIdentifier!)&referral=\(referrerAddress!)"
        : .empty

        return (baseUrl + affiliateParams).asUrl
    }

    static func buildKyberSwapTransaction(chain: String) -> URL {
        return "https://aggregator-api.kyberswap.com/\(chain)/api/v1/route/build".asUrl
    }

    static func fetchKyberSwapTokens(chainId: String) -> URL {
        return "https://ks-setting.kyberswap.com/api/v1/tokens?chainIds=\(chainId)&isWhitelisted=true&pageSize=100".asUrl
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

    static let avalancheServiceRpcService = "https://api.vultisig.com/avax/"

    static let bscServiceRpcService = "https://api.vultisig.com/bsc/"

    static let baseServiceRpcService = "https://api.vultisig.com/base/"

    static let arbitrumOneServiceRpcService = "https://api.vultisig.com/arb/"

    static let polygonServiceRpcService = "https://api.vultisig.com/polygon/"

    static let optimismServiceRpcService = "https://api.vultisig.com/opt/"

    static let cronosServiceRpcService = "https://cronos-evm-rpc.publicnode.com"

    static let blastServiceRpcService = "https://api.vultisig.com/blast/"

    static let zksyncServiceRpcService = "https://api.vultisig.com/zksync/"

    static let ethServiceRpcService = "https://api.vultisig.com/eth/"

    static let ethSepoliaServiceRpcService = "https://ethereum-sepolia-rpc.publicnode.com"

    static let mantleServiceRpcService = "https://api.vultisig.com/mantle/"

    static let hyperliquidServiceRpcService = "https://api.vultisig.com/hyperevm/"

    static let seiServiceRpcService = "https://evm-rpc.sei-apis.com"

    static let solanaServiceRpc = "https://api.vultisig.com/solana/"

    static let solanaTokenInfoServiceRpc = "https://api.solana.fm/v1/tokens"

    static func solanaTokenInfoServiceRpc2(tokenAddress: String) -> String {
        "https://api.vultisig.com/jup/tokens/v2/search?query=\(tokenAddress)"
    }

    static func solanaTokenInfoList() -> String {
        "https://api.vultisig.com/jup/tokens/v2/tag?query=verified"
    }

    static func solanaTokenQuote(inputMint: String, outputMint: String, amount: String, slippageBps: String) -> String {
        "https://quote-api.jup.ag/v6/quote?inputMint=\(inputMint)&outputMint=\(outputMint)&amount=\(amount)&slippageBps=\(slippageBps)"
    }

    static func suiTokenQuote() -> String {
        "https://api-sui.cetus.zone/v2/sui/swap/count"
    }

    // Cetus Aggregator API endpoints
    static let cetusApiBase = "https://api-sui.cetus.zone"

    static func cetusAggregatorFindRoutes() -> String {
        "\(cetusApiBase)/router_v2/find_routes"
    }

    static func cetusAggregatorSwapCount() -> String {
        "\(cetusApiBase)/v2/sui/swap/count"
    }

    // Additional Cetus endpoints for future use
    static func cetusPoolInfo() -> String {
        "\(cetusApiBase)/v2/sui/pools"
    }

    static func cetusTokenInfo() -> String {
        "\(cetusApiBase)/v2/sui/tokens"
    }

    static func cetusPriceInfo() -> String {
        "\(cetusApiBase)/v2/sui/prices"
    }

    static let rippleServiceRpc = "https://xrplcluster.com"

    static let suiServiceRpc = "https://sui-rpc.publicnode.com"

    static let polkadotServiceRpc = "https://api.vultisig.com/dot/" // "https://polkadot-rpc.publicnode.com"

    static let polkadotServiceBalance = "https://assethub-polkadot.api.subscan.io/api/v2/scan/search"

    static let tonServiceRpc = "https://api.vultisig.com/ton/v2/jsonRPC"

    static func fetchTonBalance(address: String) -> String {
        return "https://api.vultisig.com/ton/v3/addressInformation?address=\(address)&use_v2=false"
    }

    static func fetchTonJettonBalance(address: String, jettonAddress: String) -> String {
        return "\(vultisigApiProxy)/ton/v3/jetton/wallets?owner_address=\(address)&jetton_master_address=\(jettonAddress)"
    }

    static func tonApiRunGetMethod() -> String {
        return "\(vultisigApiProxy)/ton/v2/runGetMethod"
    }

    static func fetchMemoInfo(hash: String) -> URL {
        return "https://api.etherface.io/v1/signatures/hash/all/\(hash)/1".asUrl
    }

    static func fetchFourByteSignature(hexSignature: String) -> URL {
        return "https://www.4byte.directory/api/v1/signatures/?format=json&hex_signature=\(hexSignature)&ordering=created_at".asUrl
    }

    static func fetchExtendedAddressInformation(address: String) -> String {
        return "https://api.vultisig.com/ton/v2/getExtendedAddressInformation?address=\(address)"
    }

    static func broadcastTonTransaction() -> String {
        return "https://api.vultisig.com/ton/v2/sendBocReturnHash"
    }

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
    static func bitcoinBroadcast() -> URL {
        "\(vultisigApiProxy)/bitcoin/".asUrl
    }

    static func dashBroadcast() -> URL {
        "\(vultisigApiProxy)/dash/".asUrl
    }
    static func blockchairDashboard(_ address: String, _ coinName: String) -> URL {
        // ?state=latest
        "\(vultisigApiProxy)/blockchair/\(coinName)/dashboards/address/\(address)".asUrl
    }

    static func ethereumLabelTxHash(_ value: String) -> String {
        "https://etherscan.io/tx/\(value)"
    }

    static func fetchCryptoPrices(ids: String, currencies: String) -> URL {
        "\(vultisigApiProxy)/coingeicko/api/v3/simple/price?ids=\(ids)&vs_currencies=\(currencies)".asUrl
    }
    static func coinGeckoCoinsList() -> URL {
        "\(vultisigApiProxy)/coingeicko/api/v3/coins/list?include_platform=true&status=active".asUrl
    }
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

    static func fetchEthereumTransactions(_ userAddress: String) -> String {
        "https://sepolia.etherscan.io/tx/\(userAddress)"
    }

    // MARK: - Circle MSCA Endpoints

    static let circleApiBase = "\(vultisigApiProxy)/circle"

    // GET /wallet?refId=...
    static func fetchCircleWallets(refId: String) -> String {
        "\(circleApiBase)/wallet?refId=\(refId)"
    }

    // POST /create
    static func createCircleWallet() -> String {
        "\(circleApiBase)/create"
    }

    // Note: Balance and Yield are not available via this proxy.
    // We must use standard EVM RPC calls to the wallet address.

    static func fetchBitcoinTransactions(_ userAddress: String) -> String {
        "https://mempool.space/api/address/\(userAddress)/txs"
    }

    static func fetchLitecoinTransactions(_ userAddress: String) -> String {
        "https://litecoinspace.org/api/address/\(userAddress)/txs"
    }

    static func bscLabelTxHash(_ value: String) -> String {
        "https://bscscan.com/tx/\(value)"
    }

    static func resolveTNS(name: String, chain: Chain = .thorChain) -> URL {
        let baseUrl = chain == .thorChainStagenet
            ? "https://stagenet-midgard.ninerealms.com"
            : "https://midgard.ninerealms.com"
        return "\(baseUrl)/v2/thorname/lookup/\(name)".asUrl
    }

    static func fetchOsmosisAccountBalance(address: String) -> String {
        "https://osmosis-rest.publicnode.com/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchOsmosisAccountNumber(_ address: String) -> String {
        "https://osmosis-rest.publicnode.com/cosmos/auth/v1beta1/accounts/\(address)"
    }

    static let broadcastOsmosisTransaction = "https://osmosis-rest.publicnode.com/cosmos/tx/v1beta1/txs"

    static func fetchOsmosisWasmTokenBalance(contractAddress: String, base64Payload: String) -> String {
        "https://osmosis-rest.publicnode.com/cosmwasm/wasm/v1/contract/\(contractAddress)/smart/\(base64Payload)"
    }

    static func fetchOsmosisIbcDenomTraces(hash: String) -> String {
        "https://osmosis-rest.publicnode.com/ibc/apps/transfer/v1/denom_traces/\(hash)"
    }

    static func fetchOsmosisLatestBlock() -> String {
        "https://osmosis-rest.publicnode.com/cosmos/base/tendermint/v1beta1/blocks/latest"
    }

    static func fetchAkashAccountBalance(address: String) -> String {
        "https://akash-rest.publicnode.com/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchAkashAccountNumber(_ address: String) -> String {
        "https://akash-rest.publicnode.com/cosmos/auth/v1beta1/accounts/\(address)"
    }

    static let broadcastAkashTransaction = "https://akash-rest.publicnode.com/cosmos/tx/v1beta1/txs"

    static func fetchNobleAccountBalance(address: String) -> String {
        "https://noble-api.polkachu.com/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchNobleAccountNumber(_ address: String) -> String {
        "https://noble-api.polkachu.com/cosmos/auth/v1beta1/accounts/\(address)"
    }

    static let broadcastNobleTransaction = "https://noble-api.polkachu.com/cosmos/tx/v1beta1/txs"

    static func fetchCosmosAccountBalance(address: String) -> String {
        "https://cosmos-rest.publicnode.com/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchCosmosAccountNumber(_ address: String) -> String {
        "https://cosmos-rest.publicnode.com/cosmos/auth/v1beta1/accounts/\(address)"
    }

    static let broadcastCosmosTransaction = "https://cosmos-rest.publicnode.com/cosmos/tx/v1beta1/txs"

    static func fetchCosmosWasmTokenBalance(contractAddress: String, base64Payload: String) -> String {
        "https://cosmos-rest.publicnode.com/cosmwasm/wasm/v1/contract/\(contractAddress)/smart/\(base64Payload)"
    }

    static func fetchCosmosIbcDenomTraces(hash: String) -> String {
        "https://cosmos-rest.publicnode.com/ibc/apps/transfer/v1/denom_traces/\(hash)"
    }

    static func fetchCosmosLatestBlock() -> String {
        "https://cosmos-rest.publicnode.com/cosmos/base/tendermint/v1beta1/blocks/latest"
    }

    static func fetchTerraAccountBalance(address: String) -> String {
        "https://terra-lcd.publicnode.com/cosmos/bank/v1beta1/spendable_balances/\(address)"
    }
    static func fetchTerraAccountNumber(_ address: String) -> String {
        "https://terra-lcd.publicnode.com/cosmos/auth/v1beta1/accounts/\(address)"
    }

    static let broadcastTerraTransaction = "https://terra-lcd.publicnode.com/cosmos/tx/v1beta1/txs"

    static func fetchTerraIbcDenomTraces(hash: String) -> String {
        "https://terra-lcd.publicnode.com/ibc/apps/transfer/v1/denom_traces/\(hash)"
    }

    static func fetchTerraWasmTokenBalance(contractAddress: String, base64Payload: String) -> String {
        "https://terra-lcd.publicnode.com/cosmwasm/wasm/v1/contract/\(contractAddress)/smart/\(base64Payload)"
    }

    static func fetchTerraLatestBlock() -> String {
        "https://terra-lcd.publicnode.com/cosmos/base/tendermint/v1beta1/blocks/latest"
    }

    static func fetchTerraClassicAccountBalance(address: String) -> String {
        "https://terra-classic-lcd.publicnode.com/cosmos/bank/v1beta1/spendable_balances/\(address)"
    }
    static func fetchTerraClassicAccountNumber(_ address: String) -> String {
        "https://terra-classic-lcd.publicnode.com/cosmos/auth/v1beta1/accounts/\(address)"
    }

    static let broadcastTerraClassicTransaction = "https://terra-classic-lcd.publicnode.com/cosmos/tx/v1beta1/txs"

    static func fetchTerraClassicIbcDenomTraces(hash: String) -> String {
        "https://terra-classic-lcd.publicnode.com/ibc/apps/transfer/v1/denom_traces/\(hash)"
    }

    static func fetchTerraClassicWasmTokenBalance(contractAddress: String, base64Payload: String) -> String {
        "https://terra-classic-lcd.publicnode.com/cosmwasm/wasm/v1/contract/\(contractAddress)/smart/\(base64Payload)"
    }

    static func fetchTerraClassicLatestBlock() -> String {
        "https://terra-classic-lcd.publicnode.com/cosmos/base/tendermint/v1beta1/blocks/latest"
    }

    static func fetchDydxAccountBalance(address: String) -> String {
        "https://dydx-rest.publicnode.com/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchDydxAccountNumber(_ address: String) -> String {
        "https://dydx-rest.publicnode.com/cosmos/auth/v1beta1/accounts/\(address)"
    }

    static let broadcastDydxTransaction = "https://dydx-rest.publicnode.com/cosmos/tx/v1beta1/txs"

    static func fetchKujiraAccountBalance(address: String) -> String {
        "https://kujira-rest.publicnode.com/cosmos/bank/v1beta1/balances/\(address)"
    }
    static func fetchKujiraAccountNumber(_ address: String) -> String {
        "https://kujira-rest.publicnode.com/cosmos/auth/v1beta1/accounts/\(address)"
    }

    static let broadcastKujiraTransaction = "https://kujira-rest.publicnode.com/cosmos/tx/v1beta1/txs"

    static func fetchKujiraWasmTokenBalance(contractAddress: String, base64Payload: String) -> String {
        "https://kujira-rest.publicnode.com/cosmwasm/wasm/v1/contract/\(contractAddress)/smart/\(base64Payload)"
    }

    static func fetchKujiraIbcDenomTraces(hash: String) -> String {
        "https://kujira-rest.publicnode.com/ibc/apps/transfer/v1/denom_traces/\(hash)"
    }

    static func fetchKujiraLatestBlock() -> String {
        "https://kujira-rest.publicnode.com/cosmos/base/tendermint/v1beta1/blocks/latest"
    }

    static func getSwapProgressURL(txid: String) -> String {
        return "https://runescan.io/tx/\(txid.stripHexPrefix())"
    }

    static func getStagenetSwapProgressURL(txid: String) -> String {
        return "https://runescan.io/tx/\(txid.stripHexPrefix())?network=stagenet"
    }

    static func thorchainNodeExplorerURL(_ address: String) -> String {
        return "https://thorchain.net/node/\(address)"
    }

    static func getMayaSwapTracker(txid: String) -> String {
        return "https://www.explorer.mayachain.info/tx/\(txid.stripHexPrefix())"
    }

    static func getLifiSwapTracker(txid: String) -> String {
        return "https://scan.li.fi/tx/\(txid)"
    }

    static let tronEvmServiceRpc = "https://api.vultisig.com/tron/jsonrpc"

    // Cardano endpoints - Using Koios API (free, open source, no API key required)
    static let cardanoServiceRpc = "https://api.koios.rest/api/v1"

    static func fetchCardanoBalance(address: String) -> String {
        return "\(cardanoServiceRpc)/address_info"
    }

    static func fetchCardanoUTXOs(address: String) -> String {
        return "\(cardanoServiceRpc)/address_utxos"
    }

    static func getExplorerURL(chain: Chain, txid: String) -> String {
        switch chain {
        case .bitcoin:
            return "https://mempool.space/tx/\(txid)"
        case .bitcoinCash:
            return "https://blockchair.com/bitcoin-cash/transaction/\(txid)"
        case .litecoin:
            return "https://blockchair.com/litecoin/transaction/\(txid)"
        case .dogecoin:
            return "https://blockchair.com/dogecoin/transaction/\(txid)"
        case .dash:
            return "https://blockchair.com/dash/transaction/\(txid)"
        case .zcash:
            return "https://blockchair.com/zcash/transaction/\(txid)"
        case .thorChain:
            return "https://runescan.io/tx/\(txid.stripHexPrefix())"
        case .thorChainStagenet:
            return "https://runescan.io/tx/\(txid.stripHexPrefix())?network=stagenet"
        case .solana:
            return "https://orb.helius.dev/tx/\(txid)"
        case .ethereum:
            return "https://etherscan.io/tx/\(txid)"
        case .gaiaChain:
            return "https://www.mintscan.io/cosmos/tx/\(txid)"
        case .dydx:
            return "https://www.mintscan.io/dydx/tx/\(txid)"
        case .kujira:
            return "https://finder.kujira.network/kaiyo-1/tx/\(txid)"
        case .avalanche:
            return "https://snowtrace.io/tx/\(txid)"
        case .bscChain:
            return "https://bscscan.com/tx/\(txid)"
        case .mayaChain:
            return "https://www.explorer.mayachain.info/tx/\(txid)"
        case .arbitrum:
            return "https://arbiscan.io/tx/\(txid)"
        case .base:
            return "https://basescan.org/tx/\(txid)"
        case .optimism:
            return "https://optimistic.etherscan.io/tx/\(txid)"
        case .polygon, .polygonV2:
            return "https://polygonscan.com/tx/\(txid)"
        case .blast:
            return "https://blastscan.io/tx/\(txid)"
        case .cronosChain:
            return "https://cronoscan.com/tx/\(txid)"
        case .sui:
            return "https://suiscan.xyz/mainnet/tx/\(txid)"
        case .polkadot:
            return "https://assethub-polkadot.subscan.io/extrinsic/\(txid)"
        case .zksync:
            return "https://explorer.zksync.io/tx/\(txid)"
        case .ton:
            return "https://tonviewer.com/transaction/\(txid)"
        case .osmosis:
            return "https://www.mintscan.io/osmosis/tx/\(txid)"
        case .terra:
            return "https://www.mintscan.io/terra/tx/\(txid)"
        case .terraClassic:
            return "https://finder.terra.money/classic/tx/\(txid)"
        case .noble:
            return "https://www.mintscan.io/noble/tx/\(txid)"
        case .ripple:
            return "https://xrpscan.com/tx/\(txid)"
        case .akash:
            return "https://www.mintscan.io/akash/tx/\(txid)"
        case .tron:
            return "https://tronscan.org/#/transaction/\(txid)"
        case .ethereumSepolia:
            return "https://sepolia.etherscan.io/tx/\(txid)"
        case .cardano:
            return "https://cardanoscan.io/transaction/\(txid)"
        case .mantle:
            return "https://explorer.mantle.xyz/tx/\(txid)"

        case .hyperliquid:
            return "https://liquidscan.io/tx/\(txid)"
        case .sei:
            return "https://seiscan.io/tx/\(txid)"
        }
    }

    static func cardanoBroadcast() -> URL {
        return "\(vultisigApiProxy)/ada/".asUrl
    }

    static func getExplorerByAddressURL(chain: Chain, address: String) -> String? {
        switch chain {
        case .bitcoin:
            return "https://mempool.space/address/\(address)"
        case .bitcoinCash:
            return "https://blockchair.com/bitcoin-cash/address/\(address)"
        case .litecoin:
            return "https://blockchair.com/litecoin/address/\(address)"
        case .dogecoin:
            return "https://blockchair.com/dogecoin/address/\(address)"
        case .dash:
            return "https://blockchair.com/dash/address/\(address)"
        case .zcash:
            return "https://blockchair.com/zcash/address/\(address)"
        case .thorChain:
            return "https://runescan.io/address/\(address)"
        case .thorChainStagenet:
            return "https://runescan.io/address/\(address)?network=stagenet"
        case .solana:
            return "https://orb.helius.dev/address/\(address)"
        case .ethereum:
            return "https://etherscan.io/address/\(address)"
        case .ethereumSepolia:
            return "https://sepolia.etherscan.io/address/\(address)"
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
        case .mayaChain:
            return "https://www.explorer.mayachain.info/address/\(address)"
        case .arbitrum:
            return "https://arbiscan.io/address/\(address)"
        case .base:
            return "https://basescan.org/address/\(address)"
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
            return "https://assethub-polkadot.subscan.io/account/\(address)"
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
        case .cardano:
            return "https://cardanoscan.io/address/\(address)"
        case .mantle:
            return "https://mantlescan.xyz/address/\(address)"
        case .hyperliquid:
            return "https://liquidscan.io/address/\(address)"
        case .sei:
            return "https://seiscan.io/address/\(address)"
        }
    }

    static func getExplorerByCoinURL(coin: Coin) -> String? {
        // For native tokens, show the address page
        guard !coin.isNativeToken else {
            return getExplorerByAddressURL(chain: coin.chain, address: coin.address)
        }

        // For tokens, show the token/contract page
        let contractAddress = coin.contractAddress

        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .zcash:
            // UTXO chains don't have tokens, return address
            return getExplorerByAddressURL(chain: coin.chain, address: coin.address)
        case .thorChain:
            // For THORChain tokens, show the address with the token
            return "https://runescan.io/address/\(coin.address)"
        case .thorChainStagenet:
            return "https://runescan.io/address/\(coin.address)?network=stagenet"
        case .solana:
            return "https://orb.helius.dev/address/\(contractAddress)"
        case .ethereum:
            return "https://etherscan.io/token/\(contractAddress)"
        case .ethereumSepolia:
            return "https://sepolia.etherscan.io/token/\(contractAddress)"
        case .gaiaChain:
            // Cosmos tokens use IBC denoms, show address page
            return "https://www.mintscan.io/cosmos/address/\(coin.address)"
        case .dydx:
            return "https://www.mintscan.io/dydx/address/\(coin.address)"
        case .kujira:
            return "https://finder.kujira.network/kaiyo-1/address/\(coin.address)"
        case .avalanche:
            return "https://snowtrace.io/token/\(contractAddress)"
        case .bscChain:
            return "https://bscscan.com/token/\(contractAddress)"
        case .mayaChain:
            return "https://www.explorer.mayachain.info/address/\(coin.address)"
        case .arbitrum:
            return "https://arbiscan.io/token/\(contractAddress)"
        case .base:
            return "https://basescan.org/token/\(contractAddress)"
        case .optimism:
            return "https://optimistic.etherscan.io/token/\(contractAddress)"
        case .polygon, .polygonV2:
            return "https://polygonscan.com/token/\(contractAddress)"
        case .blast:
            return "https://blastscan.io/token/\(contractAddress)"
        case .cronosChain:
            return "https://cronoscan.com/token/\(contractAddress)"
        case .sui:
            return "https://suiscan.xyz/mainnet/coin/\(contractAddress)"
        case .polkadot:
            return "https://assethub-polkadot.subscan.io/account/\(coin.address)"
        case .zksync:
            return "https://explorer.zksync.io/token/\(contractAddress)"
        case .ton:
            return "https://tonviewer.com/\(contractAddress)"
        case .osmosis:
            return "https://www.mintscan.io/osmosis/address/\(coin.address)"
        case .terra:
            return "https://www.mintscan.io/terra/address/\(coin.address)"
        case .terraClassic:
            return "https://finder.terra.money/classic/address/\(coin.address)"
        case .noble:
            return "https://www.mintscan.io/noble/address/\(coin.address)"
        case .ripple:
            // XRP doesn't have traditional tokens in the same way
            return "https://xrpscan.com/account/\(coin.address)"
        case .akash:
            return "https://www.mintscan.io/akash/address/\(coin.address)"
        case .tron:
            return "https://tronscan.org/#/token20/\(contractAddress)"
        case .cardano:
            // Cardano native assets
            return "https://cardanoscan.io/token/\(contractAddress)"
        case .mantle:
            return "https://mantlescan.xyz/token/\(contractAddress)"
        case .hyperliquid:
            return "https://liquidscan.io/token/\(contractAddress)"
        case .sei:
            return "https://seiscan.io/token/\(contractAddress)"
        }
    }

    static func getExplorerByAddressURLByGroup(chain: Chain?, address: String) -> String? {
        switch chain {
        case .thorChain:
            return "https://runescan.io/address/\(address)"
        case .thorChainStagenet:
            return "https://runescan.io/address/\(address)?network=stagenet"
        case .solana:
            return "https://orb.helius.dev/address/\(address)"
        case .ethereum:
            return "https://etherscan.io/address/\(address)"
        case .ethereumSepolia:
            return "https://sepolia.etherscan.io/address/\(address)"
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
        case .zcash:
            return "https://blockchair.com/zcash/address/\(address)"
        case .mayaChain:
            return "https://www.explorer.mayachain.info/address/\(address)"
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
            return "https://assethub-polkadot.subscan.io/account/\(address)"
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
        case .cardano:
            return "https://cardanoscan.io/address/\(address)"
        case .mantle:
            return "https://mantlescan.xyz/address/\(address)"
        case .hyperliquid:
            return "https://liquidscan.io/address/\(address)"
        case .sei:
            return "https://seiscan.io/address/\(address)"
        case .none:
            return nil
        }
    }

    // Referral

    static let ReferralBase = "https://thornode.ninerealms.com/thorchain"
    static let ReferralFees = "https://thornode.ninerealms.com/thorchain/network"

    static func checkNameAvailability(for code: String) -> String {
        ReferralBase + "/thorname/lookup/\(code)"
    }

    static func getUserDetails(for code: String) -> String {
        ReferralBase + "/thorname/\(code)"
    }

    static func reverseLookup(for address: String) -> String {
        ReferralBase + "/thorname/lookup/\(address)"
    }

    static func nameLookup(for name: String) -> String {
        "https://midgard.ninerealms.com/v2/thorname/lookup/\(name)"
    }
}

fileprivate extension String {

    var asUrl: URL {
        return URL(string: self)!
    }
}
