//
//  CardanoAPI.swift
//  VultisigApp
//

import Foundation

enum CardanoAPI: TargetType {
    case tip
    case addressInfo(addresses: [String])
    case addressUtxos(addresses: [String])
    case submitTransaction(cbor: String)

    private static let koiosBaseURL = URL(string: "https://api.koios.rest")!
    private static let vultisigProxyBaseURL = URL(string: "https://api.vultisig.com")!

    var baseURL: URL {
        switch self {
        case .tip, .addressInfo, .addressUtxos:
            return Self.koiosBaseURL
        case .submitTransaction:
            return Self.vultisigProxyBaseURL
        }
    }

    var path: String {
        switch self {
        case .tip:
            return "/api/v1/tip"
        case .addressInfo:
            return "/api/v1/address_info"
        case .addressUtxos:
            return "/api/v1/address_utxos"
        case .submitTransaction:
            return "/ada/"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .tip:
            return .get
        case .addressInfo, .addressUtxos, .submitTransaction:
            return .post
        }
    }

    var task: HTTPTask {
        switch self {
        case .tip:
            return .requestPlain
        case .addressInfo(let addresses), .addressUtxos(let addresses):
            return .requestCodable(CardanoAddressesRequest(addresses: addresses), .jsonEncoding)
        case .submitTransaction(let cbor):
            return .requestCodable(
                CardanoSubmitTransactionRequest(
                    jsonrpc: "2.0",
                    method: "submitTransaction",
                    params: .init(transaction: .init(cbor: cbor)),
                    id: 1
                ),
                .jsonEncoding
            )
        }
    }

    var validationType: ValidationType {
        switch self {
        case .submitTransaction:
            // Ogmios returns HTTP 400 with a structured JSON-RPC error body for
            // error code 3117 ("already in mempool"); we need that body to detect
            // TSS-sibling duplicate broadcasts. Accept 200 + 400 here and let the
            // service decode the envelope to distinguish success vs. recoverable.
            return .customCodes([200, 400])
        default:
            return .successCodes
        }
    }
}

// MARK: - Request bodies

struct CardanoAddressesRequest: Encodable {
    let addresses: [String]

    enum CodingKeys: String, CodingKey {
        case addresses = "_addresses"
    }
}

struct CardanoSubmitTransactionRequest: Encodable {
    let jsonrpc: String
    let method: String
    let params: Params
    let id: Int

    struct Params: Encodable {
        let transaction: Transaction

        struct Transaction: Encodable {
            let cbor: String
        }
    }
}

// MARK: - Response bodies

struct CardanoTipEntry: Decodable {
    let absSlot: UInt64

    enum CodingKeys: String, CodingKey {
        case absSlot = "abs_slot"
    }
}

struct CardanoAddressInfo: Decodable {
    let balance: String
}

struct CardanoUtxoEntry: Decodable {
    let txHash: String
    let txIndex: Int
    let value: String

    enum CodingKeys: String, CodingKey {
        case txHash = "tx_hash"
        case txIndex = "tx_index"
        case value
    }
}

struct CardanoSubmitTransactionResponse: Decodable {
    let result: Result?
    let error: ErrorBody?

    struct Result: Decodable {
        let transaction: Transaction

        struct Transaction: Decodable {
            let id: String
        }
    }

    struct ErrorBody: Decodable {
        let code: Int
        let message: String?
    }
}
