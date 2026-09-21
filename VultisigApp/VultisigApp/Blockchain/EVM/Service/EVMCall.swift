//
//  EVMCall.swift
//  VultisigApp
//

import Foundation

/// How a node answered an `eth_call`.
enum EVMCallOutcome: Equatable {
    /// The call ran. `data` is the hex return data, `0x` when there is none.
    case returned(data: String)
    /// The node answered with a JSON-RPC error object.
    case failed(code: Int?, message: String?)

    /// Reads a decoded JSON-RPC response object. A response carrying neither a
    /// string `result` nor an `error` object is no answer at all, so it throws.
    init(jsonRPCResponse response: [String: Any]) throws {
        if let error = response["error"] as? [String: Any] {
            self = .failed(code: error["code"] as? Int, message: error["message"] as? String)
        } else if let result = response["result"] as? String {
            self = .returned(data: result)
        } else {
            throw RpcServiceError.rpcError(code: 500, message: "eth_call returned neither a result nor an error")
        }
    }
}

/// Runs an `eth_call` against a chain's RPC.
protocol EVMCallPerforming {
    func ethCall(chain: Chain, from: String?, to: String, data: String) async throws -> EVMCallOutcome
}

struct EvmServiceCallPerformer: EVMCallPerforming {
    func ethCall(chain: Chain, from: String?, to: String, data: String) async throws -> EVMCallOutcome {
        try await EvmService.getService(forChain: chain).ethCall(from: from, to: to, data: data)
    }
}

/// Whether an `eth_call` error is the node reporting that the call reverted, as
/// opposed to the node failing to run it (a rate limit, a missing block, a
/// malformed request). Same rule as Android's `EvmRevertReason.isExecutionRevert`.
enum EVMRevertClassifier {
    /// EIP-1474 "execution error", the code geth and its peers give a revert
    /// that carries data.
    static let executionErrorCode = 3

    /// Node boilerplate that opens a revert message. A revert without data,
    /// such as the bare `revert()` in USDT's `approve`, comes back under the
    /// generic -32000 and can only be recognised by this text.
    static let revertMessagePrefixes = [
        "execution reverted",
        "vm exception while processing transaction: revert",
        "error: transaction reverted:",
        "transaction reverted:",
        "reverted:",
        "revert:"
    ]

    static func isExecutionRevert(code: Int?, message: String?) -> Bool {
        if code == executionErrorCode {
            return true
        }
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return revertMessagePrefixes.contains { message.hasPrefix($0) }
    }
}
