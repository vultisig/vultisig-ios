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

    /// Keyless public JSON-RPC endpoints used ONLY for
    /// `getStakeMinimumDelegation`, which the Vultisig proxy blocks. The value
    /// is a network-global constant (identical on every mainnet node), used just
    /// as a form-validation floor, and never touches signing — so reading it off
    /// a public node is safe. Tried in order: PublicNode is app-friendly and
    /// keyless; mainnet-beta is the official keyless fallback. Each is a complete
    /// endpoint, so `usesProxyPath` is `false` when targeting them.
    static let minDelegationPublicHosts: [URL] = [
        URL(staticString: "https://solana-rpc.publicnode.com"),
        URL(staticString: "https://api.mainnet-beta.solana.com")
    ]

    let baseURL: URL
    /// `true` for the default Vultisig proxy (RPC under `/solana/`); `false`
    /// when a custom override supplies a complete JSON-RPC endpoint.
    let usesProxyPath: Bool
    let rpcMethod: Method

    enum Method {
        case sendTransaction(encodedTransaction: String)
        /// Dry-runs a transaction against the current bank without broadcasting.
        /// Used to prove a third-party-built transaction actually executes — and
        /// to measure its compute usage — before it is put in front of a signer.
        ///
        /// `replaceRecentBlockhash` lets the node substitute its own blockhash so
        /// a transaction can be simulated before the pre-keysign refresh
        /// installs a fresh one; passing `false` simulates the exact bytes,
        /// which is what proves a spliced blockhash is live.
        ///
        /// `accountAddresses` asks the node to return those accounts' state
        /// *after* the transaction ran. That is the only way to learn what a
        /// third-party-built transaction actually costs its payer — the fee, the
        /// rent for whatever accounts it creates, and any lamports it moves —
        /// rather than guessing at a reserve.
        case simulateTransaction(
            encodedTransaction: String,
            replaceRecentBlockhash: Bool,
            accountAddresses: [String]
        )
        case getBalance(address: String)
        case getRecentPrioritizationFees
        case getLatestBlockhash
        /// `finalized`-commitment blockhash. Used for the pre-keysign refresh:
        /// a `confirmed` blockhash isn't yet universal across the load-balanced
        /// RPC proxy's upstream nodes, so the broadcast node's preflight can
        /// return `BlockhashNotFound`. A finalized (rooted) blockhash is known
        /// to every node, eliminating that failure at the cost of ~13s of the
        /// validity window — acceptable since the refresh runs right before the
        /// ceremony.
        case getLatestBlockhashFinalized
        case getTokenAccountsByOwner(walletAddress: String, filter: TokenAccountFilter)
        case getAccountInfo(address: String)
        /// Raw (`base64`) account data for an Address Lookup Table.
        ///
        /// Deliberately not `jsonParsed`: the addresses in a lookup table are
        /// what a v0 transaction's account indices actually resolve to, so they
        /// are the ground truth every pre-signing safety check compares against.
        /// `jsonParsed` would delegate that decode to whichever node answered.
        case getAddressLookupTable(address: String)
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
        /// Network minimum active delegation (lamports) enforced by the Stake
        /// program. Takes no params. The Vultisig proxy blocks this method, so
        /// it is read from a public node; the value is a network-global constant
        /// used only as a form-validation floor and never touches signing.
        case getStakeMinimumDelegation
    }

    enum TokenAccountFilter {
        case mint(String)
        case programId(String)
    }

    var path: String {
        usesProxyPath ? Self.proxyPath : ""
    }

    var method: HTTPMethod { .post }

    /// The `TargetType` default, kept for everything the shorter one would not
    /// be an improvement for.
    static let defaultTimeout: TimeInterval = 60
    /// Short enough to sit clear of the proxy's stall boundary. Forty times the
    /// measured p99 of a healthy request through it. Repo precedent: `CetusAPI`
    /// 10 s, `StakewizValidatorMetadataProvider` 15 s, `CosmosStakingAPI` 30 s.
    static let proxyReadTimeout: TimeInterval = 20

    /// Deliberately not one number for everything.
    ///
    /// The Vultisig RPC proxy intermittently accepts a request and then parks it
    /// for a shade over 60 seconds before answering `200` — measured at
    /// 60.47–60.56 s across two dozen occurrences, a constant rather than a
    /// distribution, which is the signature of a fixed upstream timeout and a
    /// retry. The 60 s default sits exactly on that boundary, so the app spent
    /// the whole minute waiting and then usually got its answer.
    ///
    /// Three carve-outs, because the measurement is narrower than "Solana".
    ///
    /// **A custom endpoint** is not the proxy and was never measured. A user
    /// running their own node may reasonably be slower, and shortening their
    /// timeout would fix nothing they have.
    ///
    /// **A broadcast** is the one request whose outcome matters more than its
    /// latency. Aborting it does not undo it: a node that accepted the
    /// transaction is indistinguishable from one that never saw it, and the
    /// recovery path is a fresh ceremony over a fresh blockhash — different
    /// bytes, which is the one thing that could execute twice. Left long so the
    /// answer arrives rather than the question being abandoned.
    ///
    /// **The bulk reads** legitimately take a long time, and the rule for them
    /// is whether the response is bounded. `getVoteAccounts` returns the whole
    /// validator set, `getProgramAccounts` walks the stake program, and
    /// `getTokenAccountsByOwner` filtered by *program* returns every token
    /// account a wallet holds — so a slow answer there is the work, not a stall.
    /// The same call filtered by *mint* returns at most a couple of accounts and
    /// stays on the short timeout.
    var timeoutInterval: TimeInterval {
        guard usesProxyPath else { return Self.defaultTimeout }
        switch rpcMethod {
        case .sendTransaction,
             .getVoteAccounts,
             .getStakeAccountsByOwner,
             .getTokenAccountsByOwner(_, .programId):
            return Self.defaultTimeout
        default:
            return Self.proxyReadTimeout
        }
    }

    var task: HTTPTask {
        // All Solana RPC methods share a JSON-RPC envelope. Params arrays are
        // heterogeneous (String, dict) which Swift's type system can't model
        // as a clean Encodable tuple, so we lean on `.requestParameters` so
        // HTTPClient owns the JSON serialization.
        switch rpcMethod {
        case .sendTransaction(let encodedTransaction):
            // Pin the encoding: signed transactions are normalized to base64
            // before broadcast, while the RPC default is base58.
            // Pin the preflight commitment to `confirmed` to match the
            // commitment used to fetch the blockhash (getLatestBlockhash is
            // requested at `confirmed`). The sendTransaction default is
            // `finalized`, whose bank lags ~32 slots behind — so a just-fetched
            // confirmed blockhash isn't in the finalized bank yet and preflight
            // simulation fails with BlockhashNotFound. This is most visible on
            // the swap path, which refreshes to a fresh confirmed blockhash
            // immediately before keysign and broadcasts before it finalizes.
            return .requestParameters(
                rpcEnvelope(
                    method: "sendTransaction",
                    params: [encodedTransaction, ["encoding": "base64", "preflightCommitment": "confirmed"]]
                ),
                .jsonEncoding
            )
        case .simulateTransaction(let encodedTransaction, let replaceRecentBlockhash, let accountAddresses):
            // `sigVerify` is pinned off: the transactions this simulates still
            // carry an all-zero placeholder signature, and the RPC rejects the
            // combination of signature verification with blockhash replacement
            // outright. Commitment matches the blockhash fetch so the simulation
            // runs against the same bank the broadcast preflight will.
            var config: [String: Any] = [
                "encoding": "base64",
                "commitment": "confirmed",
                "sigVerify": false,
                "replaceRecentBlockhash": replaceRecentBlockhash
            ]
            // Omitted entirely when nothing was asked for: an empty `addresses`
            // array is a different request from no `accounts` key at all, and
            // some nodes reject it.
            if !accountAddresses.isEmpty {
                config["accounts"] = [
                    "encoding": "base64",
                    "addresses": accountAddresses
                ]
            }
            return .requestParameters(
                rpcEnvelope(method: "simulateTransaction", params: [encodedTransaction, config]),
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
        case .getLatestBlockhashFinalized:
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
        case .getAddressLookupTable(let address):
            return .requestParameters(
                rpcEnvelope(method: "getAccountInfo", params: [address, ["encoding": "base64", "commitment": "confirmed"]]),
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
        case .getStakeMinimumDelegation:
            return .requestParameters(rpcEnvelope(method: "getStakeMinimumDelegation", params: [] as [Any]), .jsonEncoding)
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
        /// Preflight-simulation detail. On a `-32002` simulation failure the RPC
        /// returns the program `logs` (and `err`) here — the only thing that
        /// names the actual on-chain failure. Optional: most errors omit it.
        let data: ErrorData?

        struct ErrorData: Decodable {
            let logs: [String]?
            /// Structured failure reason. Solana puts `"BlockhashNotFound"` here
            /// (with a generic `"Transaction simulation failed"` message), so the
            /// retry/expiry detection must inspect this, not just the message.
            let err: AnyCodableErr?
        }

        /// `err` is polymorphic — a bare string (`"BlockhashNotFound"`) or an
        /// object (`{"InstructionError": [...]}`). Decode just enough to expose
        /// the string form for matching.
        struct AnyCodableErr: Decodable {
            let stringValue: String?
            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                stringValue = try? container.decode(String.self)
            }
        }
    }
}

/// A JSON value of unknown shape, decoded far enough to be rendered.
///
/// `simulateTransaction`'s `err` is polymorphic: `null` on success, a bare string
/// (`"BlockhashNotFound"`) for transaction-level failures, and an object
/// (`{"InstructionError":[3,{"Custom":6003}]}`) for program failures. The
/// interesting part — which instruction failed and with what code — lives inside
/// the object form, so it cannot be flattened to a `String?`.
indirect enum SolanaRPCJSONValue: Decodable, Equatable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([SolanaRPCJSONValue])
    case object([String: SolanaRPCJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .number(String(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(String(value))
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([SolanaRPCJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: SolanaRPCJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value in Solana RPC response"
            )
        }
    }

    /// Stable rendering for logs and error messages. Object keys are sorted so
    /// the same failure always reads the same way.
    var text: String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let values):
            return "[" + values.map(\.text).joined(separator: ", ") + "]"
        case .object(let values):
            let body = values.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.text)" }
                .joined(separator: ", ")
            return "{" + body + "}"
        }
    }
}

/// `simulateTransaction` payload. `result` and `error` are mutually exclusive:
/// `error` is a transport-level JSON-RPC failure, while a transaction that ran
/// and failed comes back as a successful `result` with a non-null `value.err`.
struct SolanaSimulateTransactionResponse: Decodable {
    let result: Result?
    let error: RPCError?

    struct Result: Decodable {
        let value: Value

        struct Value: Decodable {
            let err: SolanaRPCJSONValue?
            let logs: [String]?
            let unitsConsumed: UInt64?
            /// Post-execution state of the accounts the request named, in the
            /// order they were named. `nil` when none were requested; an
            /// individual entry is null when that account does not exist.
            let accounts: [Account?]?

            struct Account: Decodable {
                let lamports: UInt64
            }
        }
    }

    struct RPCError: Decodable {
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

/// `getAccountInfo` with `encoding: base64`. A missing `value` means the account
/// does not exist, which for a lookup table is a refusal rather than an empty
/// table — an unresolvable index cannot be checked.
struct SolanaGetAccountInfoBase64Response: Decodable {
    let result: Result

    struct Result: Decodable {
        let value: Value?

        struct Value: Decodable {
            let owner: String
            /// `[payload, encoding]` — the RPC returns the encoding it used
            /// alongside the data, and it is asserted rather than assumed.
            let data: [String]
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

/// `getStakeMinimumDelegation` payload. `result.value` is the minimum active
/// delegation in lamports.
struct SolanaGetStakeMinimumDelegationResponse: Decodable {
    let result: Result

    struct Result: Decodable {
        let value: UInt64
    }
}

struct SolanaGetInflationRateResponse: Decodable {
    let result: Result

    struct Result: Decodable {
        let total: Double
        let validator: Double
        let epoch: UInt64
    }
}
