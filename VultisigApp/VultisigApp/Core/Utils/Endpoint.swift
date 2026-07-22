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
        case thorchainChainnet
        case thorchainStagenet
        case maya

        var baseUrl: String {
            switch self {
            case .thorchain:
                return "https://gateway.liquify.com/chain/thorchain_api/thorchain"
            case .thorchainChainnet:
                return "https://chainnet-thornode.thorchain.network/thorchain"
            case .thorchainStagenet:
                return "https://stagenet-thornode.thorchain.network/thorchain"
            case .maya:
                return "https://mayanode.mayachain.info/mayachain"
            }
        }
    }

    static let vultisigApiProxy = "https://api.vultisig.com"
    static let vultisigNotification = "https://api.vultisig.com/notification"
    static let supportDocumentLink = "https://docs.vultisig.com/vultisig-app-actions/managing-your-vault/vault-backup#recovering-a-lost-device"
    static let vultisigRelay = "https://api.vultisig.com/router"
    static let broadcastTransactionThorchainNineRealms = "https://gateway.liquify.com/chain/thorchain_api/cosmos/tx/v1beta1/txs"
    static let broadcastTransactionMayachain = "https://mayanode.mayachain.info/cosmos/tx/v1beta1/txs"

    // Transaction status endpoints (Midgard)
    static let thorchainMidgard = "https://gateway.liquify.com/chain/thorchain_midgard"
    static let thorchainMidgardStagenet = "https://stagenet-midgard.thorchain.network"
    static let mayachainMidgard = "https://midgard.mayachain.info"

    static let updateVersionCheck = "https://api.github.com/repos/vultisig/vultisig-ios/releases"
    static let githubMacUpdateBase = "https://github.com/vultisig/vultisig-ios/releases/tag/"
    static let githubMacDownloadBase = "https://github.com/vultisig/vultisig-ios/releases/download/"

    /// Security/Fraud Detection Services - Proxied through Vultisig API
    static let blockaidApiBase = "\(vultisigApiProxy)/blockaid/v0"

    // OFFICIAL BLOCKAID API ENDPOINTS (Working ✅)

    static let FastVaultBackupVerification = vultisigApiProxy + "/vault/verify/"

    static let thorchainNetworkInfo = "https://gateway.liquify.com/chain/thorchain_rpc/status".asUrl

    static let fetchThorchainChainnetNetworkInfoNineRealms = "https://chainnet-thornode.thorchain.network/thorchain/network"

    static let thorchainChainnetNetworkInfo = "https://chainnet-rpc.thorchain.network/status".asUrl

    static let fetchThorchainChainnetInboundAddressesNineRealms = "https://chainnet-thornode.thorchain.network/thorchain/inbound_addresses"

    static let broadcastTransactionThorchainChainnet = "https://chainnet-thornode.thorchain.network/cosmos/tx/v1beta1/txs"

    static let depositAssetsMaya = "https://mayanode.mayachain.info/mayachain/pools"

    static let fetchThorchainPools = "https://gateway.liquify.com/chain/thorchain_api/thorchain/pools"

    static let fetchThorchainChainnetPools = "https://chainnet-thornode.thorchain.network/thorchain/pools"

    static let fetchThorchainStagenetNetworkInfoNineRealms = "https://stagenet-thornode.thorchain.network/thorchain/network"

    static let thorchainStagenetNetworkInfo = "https://stagenet-rpc.thorchain.network/status".asUrl

    static let fetchThorchainStagenetInboundAddressesNineRealms = "https://stagenet-thornode.thorchain.network/thorchain/inbound_addresses"

    static let broadcastTransactionThorchainStagenet = "https://stagenet-thornode.thorchain.network/cosmos/tx/v1beta1/txs"

    static let fetchThorchainStagenetPools = "https://stagenet-thornode.thorchain.network/thorchain/pools"

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

    static let solanaTokenInfoServiceRpc = "https://api.solana.fm/v1/tokens"

    static func solanaTokenInfoServiceRpc2(tokenAddress: String) -> String {
        "https://api.vultisig.com/jup/tokens/v2/search?query=\(tokenAddress)"
    }

    static func solanaTokenInfoList() -> String {
        "https://api.vultisig.com/jup/tokens/v2/tag?query=verified"
    }

    static func solanaTokenQuote(inputMint: String, outputMint: String, amount: String, slippageBps: String) -> String {
        "https://lite-api.jup.ag/swap/v1/quote?inputMint=\(inputMint)&outputMint=\(outputMint)&amount=\(amount)&slippageBps=\(slippageBps)"
    }

    static func raydiumMintPrice(mint: String) -> String {
        "https://api-v3.raydium.io/mint/price?mints=\(mint)"
    }

    static func suiTokenQuote() -> String {
        "\(CetusAPI.cetusBaseURL.absoluteString)/v2/sui/swap/count"
    }

    static let suiServiceRpc = "https://sui-rpc.publicnode.com"

    /// Polkadot Asset Hub RPC endpoint for JSON-RPC calls (balance, broadcast,
    /// transaction status via `author_pendingExtrinsics`).
    static let polkadotServiceRpc = "https://api.vultisig.com/dot/"

    /// Bittensor RPC endpoint for JSON-RPC calls (nonce, blockHash, specVersion, etc.)
    static let bittensorServiceRpc = "https://bittensor-finney.api.onfinality.io/public"

    static func blockchairStats(_ chainName: String) -> URL {
        "\(vultisigApiProxy)/blockchair/\(chainName)/stats".asUrl
    }

    // MARK: - Circle MSCA Endpoints

    /// Base URL for the QBTC PLONK proof service (vultisig-proxied).
    /// SDK default is `https://proof.qbtc.network`; we use the proxied URL
    /// to match `vultisig-windows`. Endpoints under this base: `/health`,
    /// `/prove`. See `QBTCProofServiceAPI`.
    static let qbtcProofServiceBaseURL = "https://api.vultisig.com/qbtc-proof"

    /// Base URL for the QBTC chain REST (Cosmos SDK gRPC-gateway).
    /// Endpoints under this base: `/cosmos/auth/v1beta1/accounts/{addr}`,
    /// `/cosmos/base/tendermint/v1beta1/blocks/latest`,
    /// `/qbtc/v1/params/{name}`, `/cosmos/tx/v1beta1/txs`. See `QBTCChainAPI`.
    static let qbtcRestBaseURL = "https://api.vultisig.com/qbtc-rpc"

    static let tronEvmServiceRpc = "https://api.vultisig.com/tron-rpc"
    static let tronWalletApi = "https://api.vultisig.com/tron"

    static func getExplorerByCoinURL(coin: Coin) -> String? {
        // For native tokens, show the address page
        guard !coin.isNativeToken else {
            return ExplorerLinkBuilder.getExplorerByAddressURL(chain: coin.chain, address: coin.address)
        }

        // For tokens, show the token/contract page
        let contractAddress = coin.contractAddress

        switch coin.chain {
        case .bitcoin, .bitcoinCash, .litecoin, .dogecoin, .dash, .zcash:
            // UTXO chains don't have tokens, return address
            return ExplorerLinkBuilder.getExplorerByAddressURL(chain: coin.chain, address: coin.address)
        case .thorChain:
            // For THORChain tokens, show the address with the token
            return "https://runescan.io/address/\(coin.address)"
        case .thorChainChainnet:
            return "https://runescan.io/address/\(coin.address)?network=chainnet"
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
        case .bittensor:
            return "https://taostats.io/account/\(coin.address)"
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
            return "https://hypurrscan.io/token/\(contractAddress)"
        case .sei:
            return "https://seiscan.io/token/\(contractAddress)"
        case .qbtc:
            return nil
        }
    }

    static func getExplorerByAddressURLByGroup(chain: Chain?, address: String) -> String? {
        switch chain {
        case .thorChain:
            return "https://runescan.io/address/\(address)"
        case .thorChainChainnet:
            return "https://runescan.io/address/\(address)?network=chainnet"
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
            return "https://hypurrscan.io/address/\(address)"
        case .sei:
            return "https://seiscan.io/address/\(address)"
        case .qbtc:
            return "https://explorer.qbtc.net/qbtc/account/\(address)"
        case .bittensor:
            return "https://taostats.io/account/\(address)"
        case .none:
            return nil
        }
    }

    // MARK: - Agent

    static let agentBackendUrl = "https://agent.vultisig.com"
    static let verifierUrl = "https://verifier.vultisig.com"

    // Referral

    static let ReferralBase = "https://gateway.liquify.com/chain/thorchain_api/thorchain"
    static let ReferralFees = "https://gateway.liquify.com/chain/thorchain_api/thorchain/network"

}

private extension String {
    var asUrl: URL {
        return URL(string: self)!
    }
}
