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
        case denomMetadata(denom: String)
        case allDenomsMetadata
        case latestBlock
        case terraClassicTaxParams
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
        case .denomMetadata(let denom):
            // Denom strings can contain `/` (factory/..., ibc/HASH) which the
            // URL parser would otherwise treat as path separators. Percent-
            // encode them so the LCD receives the denom as a single segment.
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
            let encoded = denom.addingPercentEncoding(withAllowedCharacters: allowed) ?? denom
            return "/cosmos/bank/v1beta1/denoms_metadata/\(encoded)"
        case .allDenomsMetadata:
            return "/cosmos/bank/v1beta1/denoms_metadata"
        case .latestBlock:
            return "/cosmos/base/tendermint/v1beta1/blocks/latest"
        case .terraClassicTaxParams:
            // Terra Classic's proportional burn tax lives in the x/tax module,
            // not the legacy treasury module (whose tax_rate is 0). This path
            // exposes `burn_tax_rate` (currently 0.5%).
            return "/terra/tax/v1beta1/params"
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
        case .allDenomsMetadata:
            // Mirrors the SDK fallback list-fetch URL:
            // `?pagination.limit=1000`. The 1000 cap matches the SDK and is
            // large enough to enumerate every registered bank denom on Terra
            // / TerraClassic without paging.
            return .requestParameters(["pagination.limit": 1000], .urlEncoding)
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

/// Response for Terra Classic's `x/tax` params. We only consume `burn_tax_rate`
/// (a decimal string, e.g. `"0.005000000000000000"` = 0.5%).
struct TerraClassicTaxParamsResponse: Decodable {
    let params: Params

    struct Params: Decodable {
        let burnTaxRate: String

        enum CodingKeys: String, CodingKey {
            case burnTaxRate = "burn_tax_rate"
        }
    }
}
