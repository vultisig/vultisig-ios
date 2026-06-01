//
//  SolanaAPI.swift
//  VultisigApp
//

import Foundation

enum SolanaAPI: TargetType {
    case sendTransaction(encodedTransaction: String)
    case getBalance(address: String)
    case getRecentPrioritizationFees
    case getLatestBlockhash
    case getTokenAccountsByOwner(walletAddress: String, filter: TokenAccountFilter)
    case getAccountInfo(address: String)

    enum TokenAccountFilter {
        case mint(String)
        case programId(String)
    }

    private static let rpcBaseURL = URL(string: "https://api.vultisig.com")!

    /// The user's custom Solana RPC endpoint, but only when it's present AND a
    /// well-formed URL. Resolving the decision here once keeps `baseURL` and
    /// `path` from disagreeing: a non-empty-but-invalid override would otherwise
    /// make `baseURL` fall back to the default host while `path` still dropped
    /// `/solana/`, breaking routing.
    private var overrideURL: URL? {
        guard let override = CustomRPCStore.shared.url(for: .solana) else {
            return nil
        }
        return URL(string: override)
    }

    /// App-wide custom RPC override wins over the default Vultisig proxy. When a
    /// valid Solana override is set the user supplies a full JSON-RPC endpoint,
    /// so the `/solana/` proxy path is dropped (the override URL is the endpoint).
    var baseURL: URL {
        overrideURL ?? Self.rpcBaseURL
    }

    var path: String {
        // The default Vultisig proxy nests Solana RPC under `/solana/`. A valid
        // custom override is already a complete RPC endpoint, so no extra path.
        overrideURL != nil ? "" : "/solana/"
    }

    var method: HTTPMethod { .post }

    var task: HTTPTask {
        // All Solana RPC methods share a JSON-RPC envelope. Params arrays are
        // heterogeneous (String, dict) which Swift's type system can't model
        // as a clean Encodable tuple, so we lean on `.requestParameters` so
        // HTTPClient owns the JSON serialization.
        switch self {
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
