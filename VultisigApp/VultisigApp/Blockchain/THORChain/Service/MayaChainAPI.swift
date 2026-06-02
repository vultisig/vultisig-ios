//
//  MayaChainAPI.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/4/2024.
//

import Foundation

/// Pure `TargetType` for the MayaChain REST endpoints consumed by
/// `MayachainService`. The override-eligible Mayanode host is baked in at
/// construction by the service (see `MayachainService.api`); this value never
/// consults global state. The secondary Midgard surface
/// (`MayaChainBondsAPI`) has no single-chain node identity and keeps its
/// hardcoded default, mirroring how THORChain's Midgard stays on defaults.
struct MayaChainAPI: TargetType {
    /// Default Mayanode REST host; serves the Cosmos-SDK + mayanode REST surface.
    static let defaultHost = URL(string: "https://mayanode.mayachain.info")!

    enum Endpoint {
        case balances(address: String)
        case accountNumber(address: String)
        case swapQuote(
            fromAsset: String,
            toAsset: String,
            amount: String,
            destination: String,
            streamingInterval: String,
            streamingQuantity: String?,
            affiliate: String?,
            affiliateBps: String?
        )
        case broadcast(body: Data)
        case pools
    }

    let endpoint: Endpoint
    /// The resolved Mayanode host (override-aware), baked in by the service.
    let host: URL

    init(_ endpoint: Endpoint, host: URL = MayaChainAPI.defaultHost) {
        self.endpoint = endpoint
        self.host = host
    }

    var baseURL: URL { host }

    var path: String {
        switch endpoint {
        case .balances(let addr):
            return "/cosmos/bank/v1beta1/balances/\(addr)"
        case .accountNumber(let addr):
            return "/auth/accounts/\(addr)"
        case .swapQuote:
            return "/mayachain/quote/swap"
        case .broadcast:
            return "/cosmos/tx/v1beta1/txs"
        case .pools:
            return "/mayachain/pools"
        }
    }

    var method: HTTPMethod {
        switch endpoint {
        case .balances, .accountNumber, .swapQuote, .pools:
            return .get
        case .broadcast:
            return .post
        }
    }

    var task: HTTPTask {
        switch endpoint {
        case .balances, .accountNumber, .pools:
            return .requestPlain
        case .swapQuote(let from, let to, let amount, let dest, let interval, let streamingQuantity, let affiliate, let affiliateBps):
            var params: [String: Any] = [
                "from_asset": from,
                "to_asset": to,
                "amount": amount,
                "destination": dest,
                "streaming_interval": interval
            ]
            if let streamingQuantity = streamingQuantity { params["streaming_quantity"] = streamingQuantity }
            if let affiliate = affiliate { params["affiliate"] = affiliate }
            if let affiliateBps = affiliateBps { params["affiliate_bps"] = affiliateBps }
            return .requestParameters(params, .urlEncoding)
        case .broadcast(let body):
            return .requestData(body)
        }
    }

    var headers: [String: String]? {
        [
            "Content-Type": "application/json",
            "X-Client-ID": "vultisig"
        ]
    }
}
