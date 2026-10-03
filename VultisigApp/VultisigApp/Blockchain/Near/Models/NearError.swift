//
//  NearError.swift
//  VultisigApp
//

import Foundation

/// NEAR failures, typed so callers can tell a node that *answered* "there is no
/// such account / key / transaction" (a valid answer) from a transport failure
/// or a malformed body. Collapsing the two is what lets a broken RPC read as
/// zero or as "pending forever".
enum NearError: LocalizedError, Equatable {

    /// The node returned a JSON-RPC error. `name` is the RPC error name
    /// (`cause.name` when the handler nests it), which is the only part that
    /// distinguishes a timeout from a rejection from a missing record.
    case rpc(method: String, name: String, message: String)

    /// The node affirmatively answered that the entity does not exist.
    case unknownAccount(String)
    case unknownAccessKey(String)
    case unknownTransaction(String)

    /// A 2xx body that is not the JSON-RPC envelope this code can read.
    case malformedResponse(String)

    /// Signed bytes that do not carry a NEAR `TransactionV0` body plus an
    /// Ed25519 signature.
    case malformedSignedTransaction(String)

    var errorDescription: String? {
        switch self {
        case let .rpc(method, name, message):
            return String(format: "nearErrorRpc".localized, method, name, message)
        case let .unknownAccount(accountId):
            return String(format: "nearErrorUnknownAccount".localized, accountId)
        case let .unknownAccessKey(detail):
            return String(format: "nearErrorUnknownAccessKey".localized, detail)
        case let .unknownTransaction(hash):
            return String(format: "nearErrorUnknownTransaction".localized, hash)
        case let .malformedResponse(detail):
            return String(format: "nearErrorMalformedResponse".localized, detail)
        case let .malformedSignedTransaction(detail):
            return String(format: "nearErrorMalformedSignedTransaction".localized, detail)
        }
    }

    /// RPC error names nearcore uses for "this record does not exist". Read
    /// from the top level or from `cause.name`.
    static func unknownEntity(forRPCName name: String, detail: String) -> NearError? {
        switch name {
        case "UNKNOWN_ACCOUNT":
            return .unknownAccount(detail)
        case "UNKNOWN_ACCESS_KEY":
            return .unknownAccessKey(detail)
        case "UNKNOWN_TRANSACTION":
            return .unknownTransaction(detail)
        default:
            return nil
        }
    }

    var isUnknownTransaction: Bool {
        if case .unknownTransaction = self {
            return true
        }
        return false
    }

    /// The node gave up waiting rather than rejecting the transaction: the
    /// outcome is unknown, not failed.
    var isRPCWaitTimeout: Bool {
        if case let .rpc(_, name, _) = self, name == "TIMEOUT_ERROR" {
            return true
        }
        return false
    }
}
