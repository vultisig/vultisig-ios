//
//  ThorchainStagenetAPI.swift
//  VultisigApp
//
//  Created by Architecture 3.c.3 on 2026-04-23.
//

import Foundation

/// TargetType for THORChain's two test environments. The same REST shape
/// as mainnet (`ThorchainMainnetAPI`) lives here, just with different
/// hosts selected per-case via `Environment`.
///
/// Environment naming note:
///   - `.chainnet` → `chainnet-thornode.thorchain.network` — used by
///     `ThorchainStagenetService.swift` (Vultisig's internal "Stagenet-1").
///   - `.stagenet` → `stagenet-thornode.thorchain.network` — used by
///     `ThorchainStagenet2Service.swift` (Vultisig's internal "Stagenet-2").
///
/// The service-class file names and the URL prefixes disagree (historical
/// reasons documented in Endpoint.swift). Cases here use URL-prefix names
/// so readers can map enum → actual host at a glance.
///
/// Mainnet-only features (RUJI GraphQL, TCY staker, yield-token CosmWasm)
/// are NOT duplicated here — test environments don't support them. The
/// legacy code returned hardcoded zeros; we just omit the cases.
enum ThorchainStagenetAPI: TargetType {
    enum Environment {
        case chainnet
        case stagenet

        var thornodeHost: URL {
            switch self {
            case .chainnet: return URL(string: "https://chainnet-thornode.thorchain.network")!
            case .stagenet: return URL(string: "https://stagenet-thornode.thorchain.network")!
            }
        }

        var rpcStatusHost: URL {
            switch self {
            case .chainnet: return URL(string: "https://chainnet-rpc.thorchain.network")!
            case .stagenet: return URL(string: "https://stagenet-rpc.thorchain.network")!
            }
        }
    }

    // MARK: Cosmos SDK endpoints (thornode host)
    case balances(env: Environment, address: String)
    case accountNumber(env: Environment, address: String)
    case denomMetadata(env: Environment, denom: String)
    case allDenomMetadata(env: Environment)

    // MARK: THORChain REST (thornode host)
    case networkInfo(env: Environment)
    case inboundAddresses(env: Environment)
    case poolInfo(env: Environment, asset: String)
    case pools(env: Environment)
    case poolLiquidityProvider(env: Environment, asset: String, address: String)
    case swapQuote(
        env: Environment,
        fromAsset: String,
        toAsset: String,
        amount: String,
        destination: String,
        streamingInterval: String,
        affiliates: String?,
        affiliateBps: String?
    )
    case broadcast(env: Environment, body: Data)

    // MARK: RPC node
    case networkStatus(env: Environment)

    // MARK: Midgard — routed to stagenet-midgard for both environments
    case resolveTNS(name: String)

    var baseURL: URL {
        switch self {
        case .balances(let env, _), .accountNumber(let env, _),
             .denomMetadata(let env, _), .allDenomMetadata(let env),
             .networkInfo(let env), .inboundAddresses(let env),
             .poolInfo(let env, _), .pools(let env),
             .poolLiquidityProvider(let env, _, _),
             .swapQuote(let env, _, _, _, _, _, _, _),
             .broadcast(let env, _):
            return env.thornodeHost

        case .networkStatus(let env):
            return env.rpcStatusHost

        case .resolveTNS:
            return URL(string: "https://stagenet-midgard.thorchain.network")!
        }
    }

    var path: String {
        switch self {
        case .balances(_, let addr):
            return "/cosmos/bank/v1beta1/balances/\(addr)"
        case .accountNumber(_, let addr):
            return "/auth/accounts/\(addr)"
        case .denomMetadata(_, let denom):
            return "/cosmos/bank/v1beta1/denoms_metadata/\(denom)"
        case .allDenomMetadata:
            return "/cosmos/bank/v1beta1/denoms_metadata"
        case .networkInfo:
            return "/thorchain/network"
        case .inboundAddresses:
            return "/thorchain/inbound_addresses"
        case .poolInfo(_, let asset):
            return "/thorchain/pool/\(asset)"
        case .pools:
            return "/thorchain/pools"
        case .poolLiquidityProvider(_, let asset, let address):
            return "/thorchain/pool/\(asset)/liquidity_provider/\(address)"
        case .swapQuote:
            return "/thorchain/quote/swap"
        case .broadcast:
            return "/cosmos/tx/v1beta1/txs"
        case .networkStatus:
            return "/status"
        case .resolveTNS(let name):
            return "/v2/thorname/lookup/\(name)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .broadcast:
            return .post
        default:
            return .get
        }
    }

    var task: HTTPTask {
        switch self {
        case .balances, .accountNumber, .denomMetadata, .networkInfo,
             .inboundAddresses, .poolInfo, .pools, .poolLiquidityProvider,
             .networkStatus, .resolveTNS:
            return .requestPlain

        case .allDenomMetadata:
            return .requestParameters(["pagination.limit": "1000"], .urlEncoding)

        case .swapQuote(_, let from, let to, let amount, let dest, let interval, let affiliates, let affiliateBps):
            var params: [String: Any] = [
                "from_asset": from,
                "to_asset": to,
                "amount": amount,
                "destination": dest,
                "streaming_interval": interval
            ]
            if let affiliates = affiliates { params["affiliate"] = affiliates }
            if let affiliateBps = affiliateBps { params["affiliate_bps"] = affiliateBps }
            return .requestParameters(params, .urlEncoding)

        case .broadcast(_, let body):
            return .requestData(body)
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "application/json"]
    }

    var validationType: ValidationType {
        switch self {
        case .poolLiquidityProvider:
            return .customCodes([200, 404])
        default:
            return .successCodes
        }
    }
}
