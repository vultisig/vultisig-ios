//
//  SuiGraphQLResponse.swift
//  VultisigApp
//

import Foundation

/// A Sui GraphQL envelope.
///
/// GraphQL answers HTTP 200 even when it refuses the request, so the status code
/// says nothing: a populated `errors` array is the real failure signal, and an
/// envelope carrying neither `data` nor `errors` is a malformed response — never
/// an empty result.
struct SuiGraphQLResponse<T: Decodable>: Decodable {
    let data: T?
    let errors: [SuiGraphQLError]?

    /// Present only when the endpoint answered with a JSON-RPC envelope instead
    /// of a GraphQL one — i.e. the host still speaks the retired protocol. Only
    /// reachable through a user's custom RPC override, and worth detecting so
    /// that failure is diagnosable rather than "malformed response".
    let jsonrpc: String?

    var hasErrors: Bool { !(errors ?? []).isEmpty }

    /// The transport-retryable node errors: the node was reached but could not
    /// answer *this time*. Everything else is its considered verdict on the
    /// request and would read the same from any other host.
    var isRetryableNodeError: Bool {
        guard let errors, !errors.isEmpty else { return false }
        return errors.contains { error in
            guard let code = error.extensions?.code else { return false }
            return SuiGraphQLError.retryableCodes.contains(code)
        }
    }
}

struct SuiGraphQLError: Decodable {
    /// Codes that mean "ask again" rather than "this request is wrong".
    ///
    /// Kept deliberately small. A broadcast is safe to replay — Sui identifies a
    /// transaction by the digest of its signed bytes, so re-submitting identical
    /// bytes is idempotent and the node returns the existing effects rather than
    /// executing twice — but replaying a request the node has already judged
    /// only delays the same answer, and on the fund path it means sending signed
    /// material to another operator for nothing.
    static let retryableCodes: Set<String> = ["INTERNAL_SERVER_ERROR", "REQUEST_TIMEOUT"]

    let message: String?
    let extensions: Extensions?

    struct Extensions: Decodable {
        let code: String?
    }
}

/// A failure reported by, or about, the Sui RPC endpoint.
enum SuiRPCError: Error, LocalizedError, Equatable {
    /// The node parsed the request and refused it.
    case node(message: String, code: String?)
    /// Neither `data` nor `errors` came back.
    case malformedResponse
    /// The configured endpoint answered with a JSON-RPC envelope.
    case legacyJSONRPCEndpoint(host: String)

    var errorDescription: String? {
        switch self {
        case .node(let message, let code):
            guard let code else { return "Sui RPC error: \(message)" }
            return "Sui RPC error (\(code)): \(message)"
        case .malformedResponse:
            return "Sui RPC returned neither data nor errors"
        case .legacyJSONRPCEndpoint(let host):
            return """
            The custom Sui RPC \(host) speaks JSON-RPC, which Sui has retired. \
            Set a Sui GraphQL RPC URL, or reset to the default endpoint.
            """
        }
    }
}

// MARK: - Query payloads
//
// Every field is optional. GraphQL resolves an absent or unreachable branch to
// `null` rather than omitting it, and several queries select different subsets
// of the same underlying type, so no single field is guaranteed present.
//
// Scalars follow the schema, not convenience: `BigInt` arrives as a JSON string
// and can exceed `Int64`, while `UInt53` arrives as a JSON number. Typing one as
// the other fails to decode.

struct SuiBalanceData: Decodable {
    let address: AddressBalance?

    struct AddressBalance: Decodable {
        let balance: Balance?
    }

    struct Balance: Decodable {
        let totalBalance: String?
    }
}

struct SuiEpochData: Decodable {
    let epoch: Epoch?

    struct Epoch: Decodable {
        let referenceGasPrice: String?
    }
}

struct SuiCoinObjectsData: Decodable {
    let address: Owner?

    struct Owner: Decodable {
        let objects: Connection?
    }

    struct Connection: Decodable {
        let pageInfo: PageInfo?
        let nodes: [Node]?
    }

    struct PageInfo: Decodable {
        let hasNextPage: Bool?
        let endCursor: String?
    }

    struct Node: Decodable {
        let address: String?
        /// `UInt53` — a JSON number, where JSON-RPC returned a decimal string.
        let version: UInt64?
        let digest: String?
        let contents: Contents?
    }

    struct Contents: Decodable {
        let type: TypeRef?
        let json: CoinFields?
    }

    struct TypeRef: Decodable {
        let repr: String?
    }

    struct CoinFields: Decodable {
        let balance: String?
    }
}

struct SuiCoinMetadataData: Decodable {
    let coinMetadata: Fields?

    struct Fields: Decodable {
        let decimals: Int?
        let symbol: String?
        let iconUrl: String?
    }
}

struct SuiExecuteTransactionData: Decodable {
    let executeTransaction: Result?

    struct Result: Decodable {
        let effects: SuiTransactionEffectsFields?
    }
}

struct SuiSimulateTransactionData: Decodable {
    let simulateTransaction: Result?

    struct Result: Decodable {
        let effects: SuiTransactionEffectsFields?
    }
}

struct SuiTransactionData: Decodable {
    let transaction: Fields?

    struct Fields: Decodable {
        let digest: String?
        let effects: SuiTransactionEffectsFields?
    }
}

struct SuiCheckpointData: Decodable {
    let checkpoint: Checkpoint?

    struct Checkpoint: Decodable {
        let sequenceNumber: UInt64?
    }
}

/// Shared by the execute, simulate and status selections; each asks for a subset.
struct SuiTransactionEffectsFields: Decodable {
    let digest: String?
    /// The `ExecutionStatus` enum: `SUCCESS` or `FAILURE`.
    let status: String?
    let executionError: ExecutionError?
    let checkpoint: Checkpoint?
    let gasEffects: GasEffects?

    struct ExecutionError: Decodable {
        let message: String?
        let abortCode: String?
        let identifier: String?
    }

    struct Checkpoint: Decodable {
        let sequenceNumber: UInt64?
    }

    struct GasEffects: Decodable {
        let gasSummary: GasSummary?
    }

    struct GasSummary: Decodable {
        /// `UInt53` — JSON numbers, where JSON-RPC returned decimal strings.
        let computationCost: UInt64?
        let storageCost: UInt64?
        let storageRebate: UInt64?
        let nonRefundableStorageFee: UInt64?
    }

    /// The execution outcome, keeping "the node did not tell us" distinct from
    /// "the node said it failed".
    ///
    /// Collapsing the two into a boolean is what makes this dangerous: the
    /// status poller records a failure as terminal, so an unrecognised status —
    /// a field the node omitted, or an enum case Sui adds later — would
    /// permanently mark a transaction the user cannot un-mark. Only an explicit
    /// `FAILURE` is a failure; anything unrecognised stays undecided and keeps
    /// polling.
    enum Outcome {
        case succeeded
        case failed
        case undetermined
    }

    var outcome: Outcome {
        // GraphQL spells the enum uppercase where JSON-RPC used lowercase
        // `"success"`, so both spellings are accepted rather than leaving a
        // comparison that silently stops matching.
        switch status?.uppercased() {
        case "SUCCESS": return .succeeded
        case "FAILURE": return .failed
        default: return .undetermined
        }
    }

    /// The execution failure reason, or `nil` when the transaction did not abort.
    var failureReason: String? {
        guard let executionError else { return nil }
        if let message = executionError.message, !message.isEmpty { return message }
        if let identifier = executionError.identifier, !identifier.isEmpty { return identifier }
        if let abortCode = executionError.abortCode, !abortCode.isEmpty {
            return "aborted with code \(abortCode)"
        }
        return nil
    }
}
