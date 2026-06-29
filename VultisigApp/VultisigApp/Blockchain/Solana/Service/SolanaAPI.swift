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
    static let rpcBaseURL = URL(staticString: "https://api.vultisig.com")
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
        /// All validators (vote accounts), `current` + `delinquent`.
        case getVoteAccounts
        /// Stake-program accounts owned by `staker`. `dataSize:200` excludes
        /// non-stake-state accounts; the `memcmp{offset:12}` narrows to the
        /// owner's accounts. `jsonParsed` returns the full parsed delegation;
        /// the pubkey-only variant (`dataSlice{0,0}`) returns just addresses.
        case getStakeAccountsByOwner(staker: String, pubkeyOnly: Bool)
        /// Full `jsonParsed` info for a single stake account.
        case getStakeAccountInfo(address: String)
        /// Current epoch + slot progress.
        case getEpochInfo
        /// Minimum lamports for a `size`-byte account to be rent-exempt. Stake
        /// accounts pass `200`.
        case getMinimumBalanceForRentExemption(size: Int)
        /// Network inflation rate for the current epoch.
        case getInflationRate
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
            // Pin the encoding: signed transactions are normalized to base64
            // before broadcast, while the RPC default is base58.
            return .requestParameters(
                rpcEnvelope(method: "sendTransaction", params: [encodedTransaction, ["encoding": "base64"]]),
                .jsonEncoding
            )
        case .getBalance(let address):
            return .requestParameters(rpcEnvelope(method: "getBalance", params: [address]), .jsonEncoding)
        case .getRecentPrioritizationFees:
            return .requestParameters(rpcEnvelope(method: "getRecentPrioritizationFees", params: [] as [Any]), .jsonEncoding)
        case .getLatestBlockhash:
            // `confirmed` is the standard commitment for sending: it tracks the
            // tip closely, whereas `finalized` lags ~32 slots (~13s) behind and
            // burns that much of the ~60–90s blockhash validity window before
            // the keysign ceremony even starts.
            return .requestParameters(rpcEnvelope(method: "getLatestBlockhash", params: [["commitment": "confirmed"]]), .jsonEncoding)
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
        case .getVoteAccounts:
            return .requestParameters(
                rpcEnvelope(method: "getVoteAccounts", params: [["commitment": "finalized"]]),
                .jsonEncoding
            )
        case .getStakeAccountsByOwner(let staker, let pubkeyOnly):
            return .requestParameters(
                rpcEnvelope(
                    method: "getProgramAccounts",
                    params: [SolanaStakingConfig.stakeProgramId, programAccountsConfig(staker: staker, pubkeyOnly: pubkeyOnly)]
                ),
                .jsonEncoding
            )
        case .getStakeAccountInfo(let address):
            return .requestParameters(
                rpcEnvelope(method: "getAccountInfo", params: [address, ["encoding": "jsonParsed"]]),
                .jsonEncoding
            )
        case .getEpochInfo:
            return .requestParameters(rpcEnvelope(method: "getEpochInfo", params: [] as [Any]), .jsonEncoding)
        case .getMinimumBalanceForRentExemption(let size):
            return .requestParameters(
                rpcEnvelope(method: "getMinimumBalanceForRentExemption", params: [size]),
                .jsonEncoding
            )
        case .getInflationRate:
            return .requestParameters(rpcEnvelope(method: "getInflationRate", params: [] as [Any]), .jsonEncoding)
        }
    }

    /// The `getProgramAccounts` config object for the stake-by-owner scan:
    /// `dataSize:200` + a `memcmp` on the staker authority. When `pubkeyOnly`
    /// the data is sliced to zero bytes (`dataSlice{0,0}`, base64) since only
    /// the addresses are needed; otherwise the full delegation is returned
    /// `jsonParsed`.
    private func programAccountsConfig(staker: String, pubkeyOnly: Bool) -> [String: Any] {
        let filters: [[String: Any]] = [
            ["dataSize": SolanaStakingConfig.stakeStateSize],
            ["memcmp": ["offset": SolanaStakingConfig.stakerMemcmpOffset, "bytes": staker]]
        ]
        if pubkeyOnly {
            return [
                "encoding": "base64",
                "dataSlice": ["offset": 0, "length": 0],
                "filters": filters
            ]
        }
        return [
            "encoding": "jsonParsed",
            "filters": filters
        ]
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

// MARK: - Staking RPC responses

/// `getProgramAccounts` result — a flat array of rows.
struct SolanaGetProgramAccountsResponse: Decodable {
    let result: [SolanaStakeProgramAccount]
}

/// `getAccountInfo` (jsonParsed) for a stake account.
struct SolanaGetStakeAccountInfoResponse: Decodable {
    let result: Result

    struct Result: Decodable {
        let value: SolanaStakeAccountInfoValue?
    }
}

struct SolanaGetEpochInfoResponse: Decodable {
    let result: SolanaEpochInfo
}

/// `getEpochInfo` payload. `epoch` / slot fields drive activation/cooldown math.
struct SolanaEpochInfo: Codable, Hashable {
    let epoch: UInt64
    let slotIndex: UInt64
    let slotsInEpoch: UInt64
    let absoluteSlot: UInt64
}

struct SolanaGetMinimumBalanceForRentExemptionResponse: Decodable {
    let result: UInt64
}

struct SolanaGetInflationRateResponse: Decodable {
    let result: Result

    struct Result: Decodable {
        let total: Double
        let validator: Double
        let epoch: UInt64
    }
}
