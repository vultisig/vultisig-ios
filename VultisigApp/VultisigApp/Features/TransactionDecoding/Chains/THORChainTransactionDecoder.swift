//
//  THORChainTransactionDecoder.swift
//  VultisigApp
//
//  Reads THORChain memos and wasm messages only when signed content proves the
//  native or inbound route. Uncorroborated lookalike memos stay unknown.
//

import BigInt
import Foundation

struct THORChainTransactionDecoder: TransactionContentDecoder {

    /// Inbound routes may originate on any chain, so provenance gates decoding.
    let handles: Set<Chain>? = nil

    static let nativeChains: Set<Chain> = [.thorChain, .thorChainChainnet, .thorChainStagenet]

    /// Inbound memos travel with the earlier THORChain route rather than being
    /// unsigned sidecars beside it.
    private static let precedence: MemoPrecedence = .memoTravelsWithTheEarlierRoute

    func decode(_ tx: SignedTransactionContent) -> DecodedTransaction? {
        // Flat fields beside an opaque signed artifact are untrusted sidecars.
        guard let content = tx.corroborated else { return nil }

        switch provenance(of: tx, content: content) {
        case .unrelated:
            return nil

        case .native:
            if let wasm = content.wasmPayload, let decoded = decodeWasm(wasm, content: content) {
                return decoded
            }
            if let memo = content.memo(Self.precedence), let decoded = decodeMemo(memo, content: content) {
                return decoded
            }
            return decodeWireType(content)

        case .inbound:
            // Foreign-chain wasm payloads cannot be THORChain contract calls.
            guard let memo = content.memo(Self.precedence) else { return nil }
            return decodeMemo(memo, content: content)
        }
    }

    private enum Provenance {
        /// The transaction is on a THORChain-family chain.
        case native
        /// Signed content names a THORChain vault as the destination.
        case inbound
        /// Nothing corroborates THORChain, so its grammar does not apply.
        case unrelated
    }

    private func provenance(of tx: SignedTransactionContent, content: CorroboratedContent) -> Provenance {
        if Self.nativeChains.contains(tx.chain) { return .native }

        switch content.swap {
        case .thorchain, .thorchainChainnet, .thorchainStagenet:
            return .inbound
        default:
            // An active approve or non-THOR swap outranks flat destination data.
            guard content.swap == nil, content.approve == nil else {
                return .unrelated
            }
            // A cached inbound vault can corroborate signed LP destinations.
            // Cold caches refuse rather than blocking a signing screen.
            return Self.inboundVaults.corroborates(
                destination: content.toAddress,
                chain: tx.chain,
                isNative: tx.isNativeCoin
            ) ? .inbound : .unrelated
        }
    }

    /// Injectable cached-vault source; decoding never performs network reads.
    static var inboundVaults: InboundVaultCorroborating = ThorchainInboundVaults()

    // MARK: - Contract calls

    private func decodeWasm(
        _ wasm: WasmExecuteContractPayload,
        content: CorroboratedContent
    ) -> DecodedTransaction? {
        guard let operation = operation(inExecuteMsg: wasm.executeMsg) else {
            return DecodedTransaction(
                operation: .contractCall,
                amount: .unstated,
                counterparty: .contract(wasm.contractAddress),
                evidence: .wasmExecuteMsg
            )
        }

        return DecodedTransaction(
            operation: operation,
            amount: amount(for: operation, wasm: wasm, content: content),
            counterparty: .contract(wasm.contractAddress),
            evidence: .wasmExecuteMsg
        )
    }

    /// What the operation moves, in the units the signed content states them.
    private func amount(
        for operation: DecodedOperation,
        wasm: WasmExecuteContractPayload,
        content: CorroboratedContent
    ) -> DecodedAmount {
        // Mint output is execution-set; attached funds are the input, not output.
        if operation == .mint { return .unstated }

        // Multiple attached denoms are ambiguous; never present only `.first`.
        if wasm.coins.count == 1,
           let funds = wasm.coins.first,
           let units = BigInt(funds.amount), units > 0 {
            return .units(units, of: .denom(funds.denom))
        }

        // Rujira account operations put exact raw amounts in their memo.
        if let memo = content.memo(Self.precedence) {
            let fields = memo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            if fields.count > 2, !fields[1].isEmpty, let raw = BigInt(fields[2]), raw > 0 {
                return .units(raw, of: .denom(fields[1]))
            }
        }

        return .unstated
    }

    /// Parses direct Rujira JSON and base64-wrapped yVault JSON. Ambiguous action
    /// sets are refused instead of depending on dictionary order.
    private func operation(inExecuteMsg executeMsg: String) -> DecodedOperation? {
        guard let data = executeMsg.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let envelope = object["execute"] as? [String: Any],
           let encoded = envelope["msg"] as? String,
           let innerData = Data(base64Encoded: encoded),
           let inner = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any] {
            let actions = inner.keys.compactMap { vaultActions[$0] }
            return actions.count == 1 ? actions[0] : nil
        }

        return rujiraOperation(in: object, depth: 0)
    }

    private let vaultActions: [String: DecodedOperation] = [
        "deposit": .mint,
        "withdraw": .redeem
    ]

    private let rujiraActions: [String: DecodedOperation] = [
        "unbond": .unstake,
        "withdraw": .unstake,
        "bond": .stake,
        "deposit": .stake,
        "claim": .claimRewards,
        "withdraw_rewards": .claimRewards
    ]

    /// Searches one namespace level; deeper keys are action parameters.
    private func rujiraOperation(in object: [String: Any], depth: Int) -> DecodedOperation? {
        let actions = object.keys.compactMap { rujiraActions[$0] }
        if actions.count == 1 { return actions[0] }
        if actions.count > 1 { return nil }

        guard depth == 0 else { return nil }

        // Sorting keeps malformed multi-namespace messages deterministic.
        let nested = object.keys.sorted().compactMap { object[$0] as? [String: Any] }
        let found = nested.compactMap { rujiraOperation(in: $0, depth: depth + 1) }
        return found.count == 1 ? found[0] : nil
    }

    // MARK: - Memo grammar

    /// Memo heads are case-folded like THORNode. Shared THORChain/Rujira verbs
    /// are distinguished by contract-address and numeric-amount shape.
    private func decodeMemo(_ memo: String, content: CorroboratedContent) -> DecodedTransaction? {
        let fields = memo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let head = fields.first else { return nil }

        // The numeric third field separates Rujira from THORChain node memos.
        let isRujiraForm = fields.count > 2
            && fields[1].hasPrefix("thor1")
            && BigInt(fields[2]) != nil

        switch head.lowercased() {
        case "m=<":
            guard fields.count > 2 else { return nil }
            return DecodedTransaction(operation: .limitOrderCancel, amount: .unstated, evidence: .memo)

        case "=<":
            guard fields.count > 2 else { return nil }
            return DecodedTransaction(
                operation: .limitOrderPlacement,
                amount: Self.carriedAmount(content.amount),
                evidence: .memo
            )

        case "bond" where isRujiraForm:
            return rujira(.stake, fields: fields)

        case "withdraw" where isRujiraForm:
            return rujira(.unstake, fields: fields)

        case "claim" where isRujiraForm:
            return rujira(.claimRewards, fields: fields)

        case "bond":
            guard fields.count > 1, !fields[1].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .bond,
                amount: Self.carriedAmount(content.amount),
                counterparty: .node(fields[1]),
                evidence: .memo
            )

        case "unbond":
            // UNBOND carries positive base units in its third field.
            guard fields.count > 2, !fields[1].isEmpty,
                  let units = BigInt(fields[2]), units > 0 else { return nil }
            return DecodedTransaction(
                operation: .unbond,
                amount: .units(units, of: .transactionCoin),
                counterparty: .node(fields[1]),
                evidence: .memo
            )

        case "rebond":
            guard fields.count > 2, !fields[1].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .rebond,
                amount: .unstated,
                counterparty: .node(fields[1]),
                evidence: .memo
            )

        case "leave":
            guard fields.count > 1, !fields[1].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .leave,
                amount: .unstated,
                counterparty: .node(fields[1]),
                evidence: .memo
            )

        case "tcy+":
            return DecodedTransaction(
                operation: .stake,
                amount: Self.carriedAmount(content.amount),
                evidence: .memo
            )

        case "tcy-":
            guard fields.count > 1, let fraction = fraction(fields[1]) else { return nil }
            return DecodedTransaction(operation: .unstake, amount: fraction, evidence: .memo)

        case "secure+":
            guard fields.count > 1, !fields[1].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .securedAssetDeposit,
                amount: Self.carriedAmount(content.amount),
                evidence: .memo
            )

        case "secure-":
            guard fields.count > 1, !fields[1].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .securedAssetWithdraw,
                amount: Self.carriedAmount(content.amount),
                evidence: .memo
            )

        case "merge":
            guard fields.count > 1, !fields[1].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .merge,
                amount: Self.carriedAmount(content.amount),
                evidence: .memo
            )

        case "unmerge":
            // `unmerge:<token>:<shares>` states its own share count, in the
            // shares' own units.
            guard fields.count > 2, !fields[1].isEmpty,
                  let shares = BigInt(fields[2]), shares > 0 else { return nil }
            return DecodedTransaction(
                operation: .unmerge,
                amount: .units(shares, of: .denom(fields[1])),
                evidence: .memo
            )

        case "+":
            guard fields.count > 1, !fields[1].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .addLiquidity,
                amount: Self.carriedAmount(content.amount),
                counterparty: .pool(fields[1]),
                evidence: .memo
            )

        case "-":
            // Single-sided withdrawals append an asset after the third-field BPS.
            guard fields.count > 2, !fields[1].isEmpty,
                  let fraction = fraction(fields[2]) else { return nil }
            return DecodedTransaction(
                operation: .removeLiquidity,
                amount: fraction,
                counterparty: .pool(fields[1]),
                evidence: .memo
            )

        default:
            return nil
        }
    }

    private func rujira(_ operation: DecodedOperation, fields: [String]) -> DecodedTransaction? {
        guard let raw = BigInt(fields[2]), raw > 0 else { return nil }
        return DecodedTransaction(
            operation: operation,
            amount: .units(raw, of: .denom(fields[1])),
            counterparty: .contract(fields[1]),
            evidence: .memo
        )
    }

    /// Refuses out-of-range basis points rather than clamping signed intent.
    private func fraction(_ field: String) -> DecodedAmount? {
        guard let bps = Int(field), bps > 0, bps <= 10_000 else { return nil }
        return .fraction(basisPoints: bps, of: .transactionCoin)
    }

    // MARK: - Wire type

    private func decodeWireType(_ content: CorroboratedContent) -> DecodedTransaction? {
        switch content.transactionType {
        case .thorMerge:
            return DecodedTransaction(
                operation: .merge,
                amount: Self.carriedAmount(content.amount),
                evidence: .wireTransactionType
            )
        case .thorUnmerge:
            return DecodedTransaction(operation: .unmerge, amount: .unstated, evidence: .wireTransactionType)
        default:
            return nil
        }
    }
    /// Max sends expose no committed amount because signing computes it later.
    private static func carriedAmount(_ signed: SignedAmount) -> DecodedAmount {
        switch signed {
        case .committed(let raw) where raw > 0:
            return .units(raw, of: .transactionCoin)
        case .committed, .computedAtSigning:
            return .unstated
        }
    }

}
