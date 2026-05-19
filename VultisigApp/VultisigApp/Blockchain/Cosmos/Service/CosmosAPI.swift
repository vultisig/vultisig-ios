//
//  CosmosAPI.swift
//  VultisigApp
//

import Foundation

/// Unified TargetType for Cosmos-SDK REST endpoints.
///
/// All Cosmos chains share the same REST surface (`/cosmos/*`, `/ibc/*`,
/// `/cosmwasm/*`, `/cosmos/base/tendermint/*`) — only the host differs. The
/// caller hands over the chain's `baseURL` plus an `Endpoint` case; this
/// struct pins down path + method + body.
struct CosmosAPI: TargetType {
    let baseURL: URL
    let endpoint: Endpoint

    enum Endpoint {
        case balance(address: String)
        case spendableBalance(address: String)
        case accountNumber(address: String)
        case broadcastTransaction(body: Data)
        case wasmTokenBalance(contractAddress: String, base64Payload: String)
        case ibcDenomTrace(hash: String)
        case latestBlock
    }

    var path: String {
        switch endpoint {
        case .balance(let address):
            return "/cosmos/bank/v1beta1/balances/\(address)"
        case .spendableBalance(let address):
            return "/cosmos/bank/v1beta1/spendable_balances/\(address)"
        case .accountNumber(let address):
            return "/cosmos/auth/v1beta1/accounts/\(address)"
        case .broadcastTransaction:
            return "/cosmos/tx/v1beta1/txs"
        case .wasmTokenBalance(let contractAddress, let base64Payload):
            // Base64 can include `/` and `=`, which the URL parser would
            // otherwise treat as path separators / query delimiters.
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
            let encodedPayload = base64Payload.addingPercentEncoding(withAllowedCharacters: allowed) ?? base64Payload
            return "/cosmwasm/wasm/v1/contract/\(contractAddress)/smart/\(encodedPayload)"
        case .ibcDenomTrace(let hash):
            return "/ibc/apps/transfer/v1/denom_traces/\(hash)"
        case .latestBlock:
            return "/cosmos/base/tendermint/v1beta1/blocks/latest"
        }
    }

    var method: HTTPMethod {
        switch endpoint {
        case .broadcastTransaction:
            return .post
        default:
            return .get
        }
    }

    var task: HTTPTask {
        switch endpoint {
        case .broadcastTransaction(let body):
            // Signed Cosmos transactions arrive pre-serialized from the
            // keysign layer; pass the bytes through unchanged.
            return .requestData(body)
        default:
            return .requestPlain
        }
    }
}

// MARK: - Response types

struct CosmosLatestBlockResponse: Decodable {
    let block: Block

    struct Block: Decodable {
        let header: Header

        struct Header: Decodable {
            let height: String
        }
    }
}

struct CosmosWasmTokenBalanceResponse: Decodable {
    let data: BalanceData

    struct BalanceData: Decodable {
        let balance: String
    }
}
