//
//  ThorchainMainnetAPI.swift
//  VultisigApp
//
//  Created by Architecture 3.c on 2026-04-23.
//

import Foundation

/// Pure `TargetType` for the THORChain mainnet REST endpoints consumed by
/// `ThorchainService` and its extensions. The override-eligible LCD and RPC
/// hosts are baked in at construction by `ThorchainService` (see
/// `ThorchainService.mainnet`); this value never consults global state. Midgard
/// (TNS) and the Vultisig GraphQL proxy are distinct hosts with no single-chain
/// identity, so they keep their hardcoded defaults. Stagenet and Chainnet
/// variants share the same API shape on different hosts; they'll get their own
/// types so each environment stays typed.
struct ThorchainMainnetAPI: TargetType {
    /// Default THORChain LCD host; serves the Cosmos-SDK + thornode REST surface.
    static let defaultLCDHost = URL(staticString: "https://gateway.liquify.com/chain/thorchain_api")
    /// Default THORChain RPC host; serves `/status`.
    static let defaultRPCHost = URL(staticString: "https://gateway.liquify.com/chain/thorchain_rpc")

    let endpoint: Endpoint
    /// The resolved THORChain LCD host (override-aware), baked in by the service.
    let lcdHost: URL
    /// The resolved THORChain RPC host (override-aware), baked in by the service.
    let rpcHost: URL

    init(_ endpoint: Endpoint, lcdHost: URL = ThorchainMainnetAPI.defaultLCDHost, rpcHost: URL = ThorchainMainnetAPI.defaultRPCHost) {
        self.endpoint = endpoint
        self.lcdHost = lcdHost
        self.rpcHost = rpcHost
    }

    enum Endpoint {
        // MARK: Cosmos SDK endpoints (thornode)
        case balances(address: String)
        case accountNumber(address: String)
        case denomMetadata(denom: String)
        case allDenomMetadata

        // MARK: THORChain-specific endpoints (thornode)
        case networkInfo
        case inboundAddresses
        /// `/thorchain/mimir/key/<KEY>` — a single network mimir value as a bare
        /// integer body (e.g. the `EnableAdvSwapQueue` limit-swap availability
        /// gate). Parsed from raw bytes by the caller, not JSON-decoded.
        case mimir(key: String)
        case poolInfo(asset: String)
        case pools
        case securedAssets
        case poolLiquidityProvider(asset: String, address: String)
        case swapQuote(
            fromAsset: String,
            toAsset: String,
            amount: String,
            destination: String,
            streamingInterval: String,
            streamingQuantity: String?,
            affiliates: String?,
            affiliateBps: String?,
            toleranceBps: String?
        )
        case tcyStaker(address: String)
        /// `/thorchain/queue/limit_swaps[?sender=<addr>]` — every limit (`=<`)
        /// order currently RESTING in the advanced-swap queue, with each
        /// order's expiry countdown and fill state.
        ///
        /// Polled as a list rather than per-hash: one call covers all of an
        /// address's resting orders. `sender` is the SOURCE-CHAIN address, so a
        /// vault with orders from several source chains needs one call per
        /// source address in play — still far fewer than one per order.
        case limitSwapQueue(sender: String?)

        // MARK: RPC node (different host)
        case networkStatus

        // MARK: Midgard (different host; routes by chain to pick mainnet vs stagenet midgard)
        case resolveTNS(name: String, chain: Chain)

        // MARK: CosmWasm smart-query (base64 payload pinned in path)
        case tcyAutoCompoundStatus

        // MARK: GraphQL (Vultisig proxy)
        case rujiGraphQL(query: String)
    }

    var baseURL: URL {
        switch endpoint {
        case .balances, .accountNumber, .denomMetadata, .allDenomMetadata,
             .networkInfo, .inboundAddresses, .mimir, .poolInfo, .pools,
             .securedAssets, .poolLiquidityProvider, .swapQuote, .tcyStaker,
             .limitSwapQueue,
             .tcyAutoCompoundStatus:
            // CosmWasm smart-query lives on the REST/LCD host, not RPC. The LCD
            // host (balances / account / inbound addresses, the primary balance
            // path) honors the THORChain override; it falls back to the default
            // host when none is set.
            return lcdHost
        case .networkStatus:
            return rpcHost
        case .resolveTNS(_, let chain):
            let isStagenet = (chain == .thorChainChainnet || chain == .thorChainStagenet)
            return isStagenet
                ? URL(staticString: "https://stagenet-midgard.thorchain.network")
                : URL(staticString: "https://gateway.liquify.com/chain/thorchain_midgard")
        case .rujiGraphQL:
            return URL(staticString: "https://api.vultisig.com")
        }
    }

    var path: String {
        switch endpoint {
        case .balances(let addr):
            return "/cosmos/bank/v1beta1/balances/\(addr)"
        case .accountNumber(let addr):
            return "/auth/accounts/\(addr)"
        case .denomMetadata(let denom):
            // THORChain denoms can contain `/` (e.g. `x/staking-tcy`, `ibc/...`),
            // which would otherwise split into extra path components.
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
            let encodedDenom = denom.addingPercentEncoding(withAllowedCharacters: allowed) ?? denom
            return "/cosmos/bank/v1beta1/denoms_metadata/\(encodedDenom)"
        case .allDenomMetadata:
            return "/cosmos/bank/v1beta1/denoms_metadata"
        case .networkInfo:
            return "/thorchain/network"
        case .inboundAddresses:
            return "/thorchain/inbound_addresses"
        case .mimir(let key):
            // Mimir keys are stored uppercase on THORNode (matching the
            // CHURNINTERVAL convention). Uppercase defensively.
            return "/thorchain/mimir/key/\(key.uppercased())"
        case .poolInfo(let asset):
            return "/thorchain/pool/\(asset)"
        case .pools:
            return "/thorchain/pools"
        case .securedAssets:
            return "/thorchain/securedassets"
        case .poolLiquidityProvider(let asset, let address):
            return "/thorchain/pool/\(asset)/liquidity_provider/\(address)"
        case .swapQuote:
            return "/thorchain/quote/swap"
        case .tcyStaker(let addr):
            return "/thorchain/tcy_staker/\(addr)"
        case .limitSwapQueue:
            return "/thorchain/queue/limit_swaps"
        case .networkStatus:
            return "/status"
        case .tcyAutoCompoundStatus:
            // Base64-encoded CosmWasm `{"status":{}}` query for TCY staking contract.
            return "/cosmwasm/wasm/v1/contract/thor1z7ejlk5wk2pxh9nfwjzkkdnrq4p2f5rjcpudltv0gh282dwfz6nq9g2cr0/smart/eyJzdGF0dXMiOnt9fQ=="
        case .resolveTNS(let name, _):
            return "/v2/thorname/lookup/\(name)"
        case .rujiGraphQL:
            return "/ruji/api/graphql"
        }
    }

    var method: HTTPMethod {
        switch endpoint {
        case .rujiGraphQL:
            return .post
        default:
            return .get
        }
    }

    var task: HTTPTask {
        switch endpoint {
        case .balances, .accountNumber, .denomMetadata, .networkInfo,
             .inboundAddresses, .mimir, .poolInfo, .pools, .securedAssets,
             .poolLiquidityProvider, .tcyStaker, .networkStatus,
             .tcyAutoCompoundStatus, .resolveTNS:
            return .requestPlain

        case .limitSwapQueue(let sender):
            // Unfiltered, the queue returns EVERY resting order on the network.
            // Always scope it to the sender when we have one.
            guard let sender, !sender.isEmpty else { return .requestPlain }
            return .requestParameters(["sender": sender], .urlEncoding)

        case .allDenomMetadata:
            return .requestParameters(["pagination.limit": "1000"], .urlEncoding)

        case .swapQuote(let from, let to, let amount, let dest, let interval, let streamingQuantity, let affiliates, let affiliateBps, let toleranceBps):
            var params: [String: Any] = [
                "from_asset": from,
                "to_asset": to,
                "amount": amount,
                "destination": dest,
                "streaming_interval": interval
            ]
            if let streamingQuantity = streamingQuantity { params["streaming_quantity"] = streamingQuantity }
            if let affiliates = affiliates { params["affiliate"] = affiliates }
            if let affiliateBps = affiliateBps { params["affiliate_bps"] = affiliateBps }
            if let toleranceBps = toleranceBps { params["tolerance_bps"] = toleranceBps }
            return .requestParameters(params, .urlEncoding)

        case .rujiGraphQL(let query):
            return .requestParameters(["query": query], .jsonEncoding)
        }
    }

    var headers: [String: String]? {
        var base: [String: String] = ["Content-Type": "application/json"]
        switch endpoint {
        case .balances, .accountNumber, .swapQuote, .poolInfo, .pools,
             .securedAssets, .poolLiquidityProvider, .inboundAddresses, .mimir:
            // Endpoints that the legacy code marked with X-Client-ID via
            // get9RRequest(). Kept for 9Realms partner attribution.
            base["X-Client-ID"] = "vultisig"
        default:
            break
        }
        return base
    }

    /// LP positions return 404 for users without a position on a given pool;
    /// callers use `.customCodes([200, 404])` via the service layer today —
    /// expose it here so the service can just throw on other codes.
    var validationType: ValidationType {
        switch endpoint {
        case .poolLiquidityProvider:
            return .customCodes([200, 404])
        default:
            return .successCodes
        }
    }

    /// The pools list is ~100KB and is fetched inside `withRetry(maxAttempts: 3)`;
    /// the pre-migration session config used a 10s request timeout to avoid
    /// the retry chain blocking up to 3 minutes on a slow node.
    var timeoutInterval: TimeInterval {
        switch endpoint {
        case .pools:
            return 10
        default:
            return 60
        }
    }
}
