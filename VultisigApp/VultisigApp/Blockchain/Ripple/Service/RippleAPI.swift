//
//  RippleAPI.swift
//  VultisigApp
//

import Foundation

/// Pure `TargetType` for the XRP Ledger JSON-RPC endpoint consumed by
/// `RippleService`. The override-eligible host is baked in at construction by
/// the service (see `RippleService.api`); this value never consults global
/// state. The XRPL JSON-RPC scheme is path-agnostic (everything posts to `/`),
/// so a custom public node works with the same request bodies.
struct RippleAPI: TargetType {
    enum Endpoint {
        case submit(txBlob: String)
        case tx(hash: String)
        case serverState
        case accountInfo(account: String)
    }

    /// Default XRP Ledger JSON-RPC host.
    static let defaultHost = URL(staticString: "https://xrplcluster.com")

    let endpoint: Endpoint
    /// The resolved XRPL host (override-aware), baked in by the service.
    let host: URL

    init(_ endpoint: Endpoint, host: URL = RippleAPI.defaultHost) {
        self.endpoint = endpoint
        self.host = host
    }

    var baseURL: URL { host }

    var path: String { "/" }

    var method: HTTPMethod { .post }

    var task: HTTPTask {
        switch endpoint {
        case .submit(let txBlob):
            return .requestCodable(
                RippleRpcRequest(method: "submit", params: [RippleSubmitParams(txBlob: txBlob)]),
                .jsonEncoding
            )
        case .tx(let hash):
            return .requestCodable(
                RippleRpcRequest(
                    method: "tx",
                    params: [RippleTxParams(transaction: hash, binary: false, apiVersion: 2)]
                ),
                .jsonEncoding
            )
        case .serverState:
            return .requestCodable(
                RippleRpcRequest(method: "server_state", params: [RippleEmptyParams()]),
                .jsonEncoding
            )
        case .accountInfo(let account):
            return .requestCodable(
                RippleRpcRequest(
                    method: "account_info",
                    params: [RippleAccountInfoParams(account: account, ledgerIndex: "current", queue: true)]
                ),
                .jsonEncoding
            )
        }
    }
}

// MARK: - Request bodies

struct RippleRpcRequest<Params: Encodable>: Encodable {
    let jsonrpc: String = "2.0"
    let id: Int = 1
    let method: String
    let params: [Params]
}

struct RippleSubmitParams: Encodable {
    let txBlob: String

    enum CodingKeys: String, CodingKey {
        case txBlob = "tx_blob"
    }
}

struct RippleTxParams: Encodable {
    let transaction: String
    let binary: Bool
    let apiVersion: Int

    enum CodingKeys: String, CodingKey {
        case transaction
        case binary
        case apiVersion = "api_version"
    }
}

struct RippleEmptyParams: Encodable {}

struct RippleAccountInfoParams: Encodable {
    let account: String
    let ledgerIndex: String
    let queue: Bool

    enum CodingKeys: String, CodingKey {
        case account
        case ledgerIndex = "ledger_index"
        case queue
    }
}

// MARK: - Response types

struct RippleSubmitResponse: Decodable {
    let result: SubmitResult?

    struct SubmitResult: Decodable {
        let engineResult: String?
        let engineResultMessage: String?
        let txJson: TxJson?

        enum CodingKeys: String, CodingKey {
            case engineResult = "engine_result"
            case engineResultMessage = "engine_result_message"
            case txJson = "tx_json"
        }

        struct TxJson: Decodable {
            let hash: String?
        }
    }
}
