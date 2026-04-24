//
//  UTXOAPI.swift
//  VultisigApp
//

import Foundation

private let vultisigProxyBaseURL = URL(string: "https://api.vultisig.com")!

// MARK: - Bitcoin broadcast (proxy accepts raw hex as text/plain)

enum BitcoinBroadcastAPI: TargetType {
    case broadcast(signedTransaction: String)

    var baseURL: URL { vultisigProxyBaseURL }
    var path: String { "/bitcoin/" }
    var method: HTTPMethod { .post }

    var task: HTTPTask {
        switch self {
        case .broadcast(let hex):
            return .requestData(hex.data(using: .utf8) ?? Data())
        }
    }

    var headers: [String: String]? {
        ["Content-Type": "text/plain"]
    }
}

// MARK: - Blockchair (BCH/LTC/DOGE/DASH/ZEC)

enum BlockchairAPI: TargetType {
    case dashboard(address: String, chain: String)
    case broadcast(chain: String, signedTransaction: String)
    case stats(chain: String)

    var baseURL: URL { vultisigProxyBaseURL }

    var path: String {
        switch self {
        case .dashboard(let address, let chain):
            return "/blockchair/\(chain.lowercased())/dashboards/address/\(address)"
        case .broadcast(let chain, _):
            return "/blockchair/\(chain.lowercased())/push/transaction"
        case .stats(let chain):
            return "/blockchair/\(chain.lowercased())/stats"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .dashboard, .stats:
            return .get
        case .broadcast:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .dashboard, .stats:
            return .requestPlain
        case .broadcast(_, let signedTransaction):
            return .requestCodable(BlockchairBroadcastRequest(data: signedTransaction), .jsonEncoding)
        }
    }

    var validationType: ValidationType {
        switch self {
        case .broadcast:
            // Blockchair returns HTTP 400 with a JSON body containing a
            // `context.error` string when the transaction is invalid; accept
            // 400 so the service can surface that reason.
            return .customCodes([200, 400])
        default:
            return .successCodes
        }
    }
}

struct BlockchairBroadcastRequest: Encodable {
    let data: String
}

struct BlockchairBroadcastResponse: Decodable {
    let data: ResponseData?
    let context: Context?

    struct ResponseData: Decodable {
        let transactionHash: String?

        enum CodingKeys: String, CodingKey {
            case transactionHash = "transaction_hash"
        }
    }

    struct Context: Decodable {
        let error: String?
    }
}

// MARK: - Dash JSON-RPC (`getaddressutxos` etc.)

enum DashRpcAPI: TargetType {
    case getAddressUtxos(addresses: [String])

    var baseURL: URL { vultisigProxyBaseURL }
    var path: String { "/dash/" }
    var method: HTTPMethod { .post }

    var task: HTTPTask {
        switch self {
        case .getAddressUtxos(let addresses):
            return .requestCodable(
                DashRpcRequest(
                    method: "getaddressutxos",
                    params: [["addresses": addresses]]
                ),
                .jsonEncoding
            )
        }
    }
}

struct DashRpcRequest: Encodable {
    let jsonrpc: String = "1.0"
    let id: String = "vultisig"
    let method: String
    let params: [[String: [String]]]
}

struct DashRpcResponse<T: Decodable>: Decodable {
    let result: T?
    let error: DashRpcError?
    let id: String?
}

struct DashRpcError: Decodable {
    let code: Int
    let message: String
}

struct DashUtxo: Decodable {
    let address: String
    let txid: String
    let outputIndex: Int
    let script: String
    let satoshis: Int64
    let height: Int
}
