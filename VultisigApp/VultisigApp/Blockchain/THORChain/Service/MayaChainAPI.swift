//
//  MayaChainAPI.swift
//  VultisigApp
//
//  Created by Johnny Luo on 17/4/2024.
//

import Foundation

/// TargetType for the MayaChain REST endpoints consumed by MayachainService.
enum MayaChainAPI: TargetType {
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

    var baseURL: URL { URL(string: "https://mayanode.mayachain.info")! }

    var path: String {
        switch self {
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
        switch self {
        case .balances, .accountNumber, .swapQuote, .pools:
            return .get
        case .broadcast:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
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
