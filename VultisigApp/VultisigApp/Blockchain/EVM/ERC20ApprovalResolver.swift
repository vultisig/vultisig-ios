//
//  ERC20ApprovalResolver.swift
//  VultisigApp
//

import BigInt
import Foundation

/// What the ERC-20 approval ahead of a spend has to do.
enum ERC20ApprovalRequirement: Hashable {
    /// The current allowance already covers the amount.
    case notRequired
    /// A single `approve(spender, amount)`.
    case approve
    /// `approve(spender, 0)` before `approve(spender, amount)`: the token
    /// rejects a non-zero to non-zero approve while a stale allowance remains
    /// (USDT and the tokens that copy it).
    case resetThenApprove

    /// The payload that asks every signer for these legs, or nil when there are none.
    func approvePayload(amount: BigInt, spender: String) -> ERC20ApprovePayload? {
        switch self {
        case .notRequired:
            return nil
        case .approve:
            return ERC20ApprovePayload(amount: amount, spender: spender)
        case .resetThenApprove:
            return ERC20ApprovePayload(amount: amount, spender: spender, resetAllowanceFirst: true)
        }
    }
}

/// `spender` pulling `amount` of `token` from `owner` on `chain`.
struct ERC20ApprovalQuery: Hashable {
    let chain: Chain
    let token: String
    let owner: String
    let spender: String
    let amount: BigInt
}

extension ERC20ApprovalQuery {
    /// `spender` pulling `amount` of `coin` from the vault address that holds it.
    init(coin: Coin, spender: String, amount: BigInt) {
        self.init(chain: coin.chain, token: coin.contractAddress, owner: coin.address, spender: spender, amount: amount)
    }
}

protocol ERC20ApprovalResolving {
    func requirement(for query: ERC20ApprovalQuery) async throws -> ERC20ApprovalRequirement
}

extension ERC20ApprovalResolving {
    func decision(for query: ERC20ApprovalQuery) async throws -> ERC20ApprovalDecision {
        ERC20ApprovalDecision(query: query, requirement: try await requirement(for: query))
    }
}

/// The approval read once, on the way into Verify, together with the exact
/// spend it was read for. Verify shows it and signing uses it as is: nothing
/// reads the allowance again at sign time, so an allowance that changes in
/// between can still make the approve revert on chain.
struct ERC20ApprovalDecision: Hashable {
    let query: ERC20ApprovalQuery
    let requirement: ERC20ApprovalRequirement

    /// Whether at least one approve transaction is signed ahead of the spend.
    var signsApprove: Bool {
        requirement != .notRequired
    }

    /// The approve payload for the spend about to be signed, taken from the
    /// decision rather than the chain. `query` is nil when the spend needs no
    /// approve at all. When it needs one, the decision must have been made for
    /// exactly this spend (token, owner, spender and amount), or this throws:
    /// signing an approve decided for another spender, or skipping one because
    /// of it, is never safe.
    static func approvePayload(
        signing query: ERC20ApprovalQuery?,
        decision: ERC20ApprovalDecision?
    ) throws -> ERC20ApprovePayload? {
        guard let query else {
            return nil
        }
        guard let decision, decision.query == query else {
            throw ERC20ApprovalDecisionError.stale
        }
        return decision.requirement.approvePayload(amount: query.amount, spender: query.spender)
    }
}

enum ERC20ApprovalDecisionError: LocalizedError {
    /// The spend being signed is not the one the approval was read for.
    case stale

    var errorDescription: String? {
        "swapErrorUnexpectedDescription".localized
    }
}

/// Reads the approval a spend needs from the chain. When a non-zero allowance
/// falls short, `approve(spender, amount)` is simulated from the owner, and a
/// revert means the token wants the allowance reset to zero first. The
/// simulation is the only signal, no token list. A read or simulation the node
/// could not answer throws instead of settling either way on a guess.
struct ERC20ApprovalResolver: ERC20ApprovalResolving {
    var rpc: EVMCallPerforming = EvmServiceCallPerformer()

    func requirement(for query: ERC20ApprovalQuery) async throws -> ERC20ApprovalRequirement {
        let allowance = try await allowance(for: query)
        if allowance >= query.amount {
            return .notRequired
        }
        // A zero allowance never trips the non-zero to non-zero guard.
        if allowance == 0 {
            return .approve
        }
        return try await approveReverts(for: query) ? .resetThenApprove : .approve
    }

    func allowance(for query: ERC20ApprovalQuery) async throws -> BigInt {
        let data = try EthereumFunction.allowanceErc20Encoder(owner: query.owner, spender: query.spender)
        switch try await rpc.ethCall(chain: query.chain, from: nil, to: query.token, data: data) {
        case let .returned(result):
            // One uint256 word. `0x` from an address with no code, or a
            // truncated reply, is not an allowance.
            guard let allowance = Self.uint256(returnData: result) else {
                throw RpcServiceError.rpcError(code: 500, message: "Unexpected allowance result: \(result)")
            }
            return allowance
        case let .failed(code, message):
            throw RpcServiceError.rpcError(code: code ?? -1, message: message ?? "allowance call failed")
        }
    }

    /// Whether `approve(spender, amount)` sent by the owner would revert now.
    func approveReverts(for query: ERC20ApprovalQuery) async throws -> Bool {
        let data = try EthereumFunction.approvalErc20Encoder(address: query.spender, amount: query.amount)
        switch try await rpc.ethCall(chain: query.chain, from: query.owner, to: query.token, data: data) {
        case let .returned(result):
            // Raw return data, not a decoded bool: USDT's approve returns none.
            guard Self.isHexData(result) else {
                throw RpcServiceError.rpcError(code: 500, message: "Unexpected approve simulation result: \(result)")
            }
            return false
        case let .failed(code, message):
            if EVMRevertClassifier.isExecutionRevert(code: code, message: message) {
                return true
            }
            throw RpcServiceError.rpcError(code: code ?? -1, message: message ?? "approve simulation failed")
        }
    }

    /// `0x`-prefixed whole bytes, the shape of any `eth_call` return data.
    static func isHexData(_ value: String) -> Bool {
        guard value.hasPrefix("0x") else { return false }
        let digits = value.dropFirst(2)
        return digits.count.isMultiple(of: 2) && digits.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    static func uint256(returnData: String) -> BigInt? {
        guard isHexData(returnData), returnData.count == 2 + 64 else { return nil }
        return BigInt(String(returnData.dropFirst(2)), radix: 16)
    }
}
