//
//  Endpoint.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-05.
//

import Foundation

class Endpoint {

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
        // For native tokens, show the address page.
        guard !coin.isNativeToken else {
            return ExplorerLinkBuilder.getExplorerByAddressURL(chain: coin.chain, address: coin.address)
        }

        guard let config = ExplorerLinkBuilder.explorers[coin.chain] else { return nil }

        // Chains with a dedicated contract/token page build it from the contract
        // address; the rest reuse the holder's address page (UTXO and Cosmos
        // chains have no per-token page). qBTC is the sole exception: it exposes
        // an address explorer but no token page, so a non-native token has none.
        if let token = config.token {
            return token(coin.contractAddress)
        }
        guard coin.chain != .qbtc else { return nil }
        return config.address(coin.address)
    }

    static func getExplorerByAddressURLByGroup(chain: Chain?, address: String) -> String? {
        guard let chain else { return nil }
        return ExplorerLinkBuilder.getExplorerByAddressURL(chain: chain, address: address)
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
