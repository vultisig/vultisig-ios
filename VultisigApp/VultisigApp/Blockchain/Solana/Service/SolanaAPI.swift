//
//  SolanaAPI.swift
//  VultisigApp
//

import Foundation

/// Pure `TargetType` for Solana JSON-RPC. The resolved `baseURL` and the
/// `/solana/` proxy-path decision are baked in by `SolanaService` at
/// construction (see `SolanaService.api`); this value never consults global
/// state. Coupling `baseURL` and `usesProxyPath` in one value keeps them from
/// disagreeing — a custom override drops the proxy path, the default keeps it.
struct SolanaAPI: TargetType {
    /// The default Vultisig proxy host. Solana RPC is nested under `/solana/`.
    static let rpcBaseURL = URL(string: "https://api.vultisig.com")!
    /// The proxy path appended to the default host.
    static let proxyPath = "/solana/"

    let baseURL: URL
    /// `true` for the default Vultisig proxy (RPC under `/solana/`); `false`
    /// when a custom override supplies a complete JSON-RPC endpoint.
    let usesProxyPath: Bool
    let rpcMethod: Method

    enum Method {
        case sendTransaction(encodedTransaction: String)
        case getBalance(address: String)
        case getRecentPrioritizationFees
        case getLatestBlockhash
        case getTokenAccountsByOwner(walletAddress: String, filter: TokenAccountFilter)
        case getAccountInfo(address: String)
    }

    enum TokenAccountFilter {
        case mint(String)
        case programId(String)
    }

    var path: String {
        usesProxyPath ? Self.proxyPath : ""
    }

    var method: HTTPMethod { .post }

    var task: HTTPTask {
        // All Solana RPC methods share a JSON-RPC envelope. Params arrays are
        // heterogeneous (String, dict) which Swift's type system can't model
        // as a clean Encodable tuple, so we lean on `.requestParameters` so
        // HTTPClient owns the JSON serialization.
        switch rpcMethod {
        case .sendTransaction(let encodedTransaction):
            return .requestParameters(rpcEnvelope(method: "sendTransaction", params: [encodedTransaction]), .jsonEncoding)
        case .getBalance(let address):
            return .requestParameters(rpcEnvelope(method: "getBalance", params: [address]), .jsonEncoding)
        case .getRecentPrioritizationFees:
            return .requestParameters(rpcEnvelope(method: "getRecentPrioritizationFees", params: [] as [Any]), .jsonEncoding)
        case .getLatestBlockhash:
            return .requestParameters(rpcEnvelope(method: "getLatestBlockhash", params: [["commitment": "finalized"]]), .jsonEncoding)
        case .getTokenAccountsByOwner(let walletAddress, let filter):
            let filterDict: [String: String]
            switch filter {
            case .mint(let mint):
                filterDict = ["mint": mint]
            case .programId(let programId):
                filterDict = ["programId": programId]
            }
            return .requestParameters(
                rpcEnvelope(method: "getTokenAccountsByOwner", params: [walletAddress, filterDict, ["encoding": "jsonParsed"]]),
                .jsonEncoding
            )
        case .getAccountInfo(let address):
            return .requestParameters(
                rpcEnvelope(method: "getAccountInfo", params: [address, ["encoding": "jsonParsed"]]),
                .jsonEncoding
            )
        }
    }

    private func rpcEnvelope(method: String, params: [Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": 1, "method": method, "params": params]
    }
}

// MARK: - Response types

struct SolanaSendTransactionResponse: Decodable {
    let result: String?
    let error: Error?

    struct Error: Decodable {
        let code: Int
        let message: String
    }
}

struct SolanaGetBalanceResponse: Decodable {
    let result: Result

    struct Result: Decodable {
        let value: Int64
    }
}

struct SolanaGetLatestBlockhashResponse: Decodable {
    let result: Result

    struct Result: Decodable {
        let value: Value

        struct Value: Decodable {
            let blockhash: String
        }
    }
}

struct SolanaGetRecentPrioritizationFeesResponse: Decodable {
    let result: [Item]

    struct Item: Decodable {
        let prioritizationFee: UInt64
    }
}

struct SolanaGetAccountInfoResponse: Decodable {
    let result: Result

    struct Result: Decodable {
        let value: Value?

        struct Value: Decodable {
            let owner: String
        }
    }
}
