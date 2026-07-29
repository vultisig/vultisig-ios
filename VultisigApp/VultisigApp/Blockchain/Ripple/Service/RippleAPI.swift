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
        /// One page of the account's trust lines. `marker` is the opaque cursor
        /// echoed by the previous page; `nil` requests the first page.
        case accountLines(account: String, marker: String?)
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
        case .accountLines(let account, let marker):
            return .requestCodable(
                RippleRpcRequest(
                    method: "account_lines",
                    params: [
                        RippleAccountLinesParams(
                            account: account,
                            ledgerIndex: "current",
                            ignoreDefault: true,
                            marker: marker
                        )
                    ]
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

struct RippleAccountLinesParams: Encodable {
    let account: String
    let ledgerIndex: String
    /// Excludes trust lines in the default state (zero balance, zero limit, no
    /// flags). Those hold nothing, so dropping them server-side keeps the pages
    /// meaningful without changing any balance we would report.
    let ignoreDefault: Bool
    /// Pagination cursor from the previous page. `nil` is omitted from the
    /// encoded body entirely, which is how the first page is requested.
    let marker: String?

    enum CodingKeys: String, CodingKey {
        case account
        case ledgerIndex = "ledger_index"
        case ignoreDefault = "ignore_default"
        case marker
    }
}

// MARK: - Response types

struct RippleSubmitResponse: Decodable {
    let result: SubmitResult?

    struct SubmitResult: Decodable {
        let engineResult: String?
        let engineResultMessage: String?
        let txJson: TxJson?
        /// Node-level error (e.g. `amendmentBlocked`) returned in an HTTP-200
        /// body when the backend can't process the request at all.
        let error: String?

        enum CodingKeys: String, CodingKey {
            case engineResult = "engine_result"
            case engineResultMessage = "engine_result_message"
            case txJson = "tx_json"
            case error
        }

        struct TxJson: Decodable {
            let hash: String?
        }
    }
}

extension RippleSubmitResponse: RippleRPCResponse {
    var rpcError: String? { result?.error }
}

struct RippleAccountLinesResponse: Decodable {
    let result: Result?

    struct Result: Decodable {
        let lines: [RippleTrustLine]?
        /// Present only while more pages remain. Typed as `String` because both
        /// rippled and Clio serialize the `account_lines` marker as one, and it
        /// is the only shape the typed request body can echo back. The XRPL API
        /// documents markers as opaque values that are "not necessarily a
        /// string", so a structured marker fails the decode — deliberately:
        /// dropping an unusable marker would silently truncate the trust-line
        /// set and under-report balances, which is the exact failure pagination
        /// exists to prevent, while a thrown error leaves the last known
        /// balance in place.
        let marker: String?
        /// rippled error token returned in an HTTP-200 error body — `actNotFound`
        /// for an unfunded account, or a node-level token that drives the retry.
        let error: String?
    }
}

extension RippleAccountLinesResponse: RippleRPCResponse {
    var rpcError: String? { result?.error }
}
