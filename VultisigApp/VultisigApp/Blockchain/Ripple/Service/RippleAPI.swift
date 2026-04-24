//
//  RippleAPI.swift
//  VultisigApp
//

import Foundation

enum RippleAPI: TargetType {
    case submit(txBlob: String)
    case serverState
    case accountInfo(account: String)

    private static let xrplBaseURL = URL(string: "https://xrplcluster.com")!

    var baseURL: URL { Self.xrplBaseURL }

    var path: String { "/" }

    var method: HTTPMethod { .post }

    var task: HTTPTask {
        switch self {
        case .submit(let txBlob):
            return .requestCodable(
                RippleRpcRequest(method: "submit", params: [RippleSubmitParams(txBlob: txBlob)]),
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
