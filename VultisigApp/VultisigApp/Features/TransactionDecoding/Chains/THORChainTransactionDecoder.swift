//
//  THORChainTransactionDecoder.swift
//  VultisigApp
//
//  Reading a THORChain operation off the two things that reach the chain: the
//  memo it parses, and the wasm execute message it runs.
//
//  ⚠️ **A memo resembling THORChain syntax is not proof of a THORChain
//  operation.** This decoder went through both wrong answers before arriving
//  here. Scoped to `coin.chain == .thorChain` it missed nearly every real
//  instance, because these memos are INBOUND — an LP add or a `SECURE+` leaves
//  Bitcoin or Ethereum carrying a THORChain memo. Opened up to every chain it
//  claimed transactions that merely looked similar: `FunctionCallCustom` lets a
//  user type any memo at all, so `+:foo` on Cardano became an LP add.
//
//  What settles it is PROVENANCE — whether anything signed corroborates that
//  THORChain is the destination:
//
//  - On a THORChain-family chain the grammar is native and needs no
//    corroboration.
//  - Off it, the transaction must carry a THORChain-family swap payload, which
//    names the vault the deposit is bound for. That is the router-deposit shim
//    every ERC-20 LP add and `SECURE+` rides.
//  - With neither, the reading is refused. An inbound UTXO memo with nothing to
//    corroborate it therefore stays `.unknown` rather than being guessed — the
//    destination vault rotates and cannot be checked without a network read,
//    and decoding does not do those.
//

import BigInt
import Foundation

struct THORChainTransactionDecoder: TransactionContentDecoder {

    /// Any chain, but only where provenance corroborates it — see `provenance`.
    let handles: Set<Chain>? = nil

    static let nativeChains: Set<Chain> = [.thorChain, .thorChainChainnet, .thorChainStagenet]

    func decode(_ tx: SignedTransactionContent) -> DecodedTransaction? {
        switch provenance(of: tx) {
        case .unrelated:
            return nil

        case .native:
            if let wasm = tx.wasmPayload, let decoded = decodeWasm(wasm, tx: tx) {
                return decoded
            }
            if let memo = tx.signedMemo, let decoded = decodeMemo(memo, tx: tx) {
                return decoded
            }
            return decodeWireType(tx)

        case .inbound:
            // ⚠️ Only the memo. A contract call is executed BY THORChain, so it
            // cannot have been sent inbound from another chain, and inspecting a
            // foreign chain's wasm payload with this grammar is how an unrelated
            // contract came to be read as a Rujira operation.
            guard let memo = tx.signedMemo else { return nil }
            return decodeMemo(memo, tx: tx)
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

    private func provenance(of tx: SignedTransactionContent) -> Provenance {
        if Self.nativeChains.contains(tx.coin.chain) { return .native }

        switch tx.swap {
        case .thorchain, .thorchainChainnet, .thorchainStagenet:
            return .inbound
        default:
            return .unrelated
        }
    }

    // MARK: - Contract calls

    private func decodeWasm(
        _ wasm: WasmExecuteContractPayload,
        tx: SignedTransactionContent
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
            amount: amount(for: operation, wasm: wasm, tx: tx),
            counterparty: .contract(wasm.contractAddress),
            evidence: .wasmExecuteMsg
        )
    }

    /// What the operation moves, in the units the signed content states them.
    private func amount(
        for operation: DecodedOperation,
        wasm: WasmExecuteContractPayload,
        tx: SignedTransactionContent
    ) -> DecodedAmount {
        // ⚠️ A vault deposit attaches what it SPENDS. How much receipt token it
        // mints is settled at execution and appears nowhere in the signed
        // content, so quoting the input beside the word "mint" would name a
        // figure for a quantity nobody knows.
        if operation == .mint { return .unstated }

        if let funds = wasm.coins.first, let units = BigInt(funds.amount), units > 0 {
            return .units(units, of: .denom(funds.denom))
        }

        // Rujira's account operations attach no funds and put the exact raw
        // amount in the memo instead: `withdraw:<contract>:<raw>`.
        if let memo = tx.signedMemo {
            let fields = memo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            if fields.count > 2, !fields[1].isEmpty, let raw = BigInt(fields[2]), raw > 0 {
                return .units(raw, of: .denom(fields[1]))
            }
        }

        return .unstated
    }

    /// The action a wasm execute message performs.
    ///
    /// ⚠️ **Parsed as JSON, not matched as a substring**, because the two shapes
    /// in use disagree about where the action is. Rujira sends it in the clear —
    /// `{"liquid":{"unbond":{}}}` — while a yVault operation wraps it in an
    /// affiliate envelope whose inner message is BASE64.
    ///
    /// ⚠️ **Ambiguity is refused, not resolved.** A message naming two actions
    /// has no defined winner, and picking one by dictionary order would let two
    /// devices read the same bytes differently.
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

    /// Rujira nests its action one level under a namespace (`liquid`, `account`),
    /// so the search goes two deep and no further — below that is the action's
    /// own parameters, and `{"withdraw":{"slippage":…}}` must not be read as a
    /// "slippage" operation.
    private func rujiraOperation(in object: [String: Any], depth: Int) -> DecodedOperation? {
        let actions = object.keys.compactMap { rujiraActions[$0] }
        if actions.count == 1 { return actions[0] }
        if actions.count > 1 { return nil }

        guard depth == 0 else { return nil }

        // Sorted so a malformed message with several namespaces resolves the
        // same way on every device rather than by dictionary order.
        let nested = object.keys.sorted().compactMap { object[$0] as? [String: Any] }
        let found = nested.compactMap { rujiraOperation(in: $0, depth: depth + 1) }
        return found.count == 1 ? found[0] : nil
    }

    // MARK: - Memo grammar

    /// ⚠️ **Heads are case-FOLDED, and the one genuine ambiguity is resolved by
    /// shape instead.** THORNode lowercases a memo's head before parsing it and
    /// the published grammar spells these uppercase, so a case-sensitive match
    /// silently dropped memos another client had every right to send.
    ///
    /// That leaves `bond`, `withdraw` and `claim`, which THORChain and Rujira
    /// both use for different things. They are told apart by their second field:
    /// Rujira addresses a CONTRACT (`thor1…`), THORChain addresses a node or a
    /// pool (`BTC.BTC`). Shape is the honest discriminator; letter case was an
    /// accident of how each happened to be written.
    private func decodeMemo(_ memo: String, tx: SignedTransactionContent) -> DecodedTransaction? {
        let fields = memo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let head = fields.first else { return nil }

        // Rujira's form is `<verb>:<contract>:<raw>` — a `thor1…` contract and a
        // NUMERIC amount. THORChain's node bond is `BOND:<node>[:<provider>]`,
        // whose optional third field is an address. Requiring the number is what
        // keeps a bond with a provider from being mistaken for a Rujira stake
        // and then refused when the provider fails to parse as an amount.
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
                amount: .units(tx.toAmountRaw, of: .transactionCoin),
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
                amount: .units(tx.toAmountRaw, of: .transactionCoin),
                counterparty: .node(fields[1]),
                evidence: .memo
            )

        case "unbond":
            // ⚠️ The amount is in the memo, in base units, over a zero-amount
            // deposit. Reading it is the only way to state a quantity here.
            guard fields.count > 2, !fields[1].isEmpty, let units = BigInt(fields[2]) else { return nil }
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
                amount: .units(tx.toAmountRaw, of: .transactionCoin),
                evidence: .memo
            )

        case "tcy-":
            guard fields.count > 1, let fraction = fraction(fields[1]) else { return nil }
            return DecodedTransaction(operation: .unstake, amount: fraction, evidence: .memo)

        case "secure+":
            guard fields.count > 1, !fields[1].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .securedAssetDeposit,
                amount: .units(tx.toAmountRaw, of: .transactionCoin),
                evidence: .memo
            )

        case "secure-":
            guard fields.count > 1, !fields[1].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .securedAssetWithdraw,
                amount: .units(tx.toAmountRaw, of: .transactionCoin),
                evidence: .memo
            )

        case "merge":
            guard fields.count > 1, !fields[1].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .merge,
                amount: .units(tx.toAmountRaw, of: .transactionCoin),
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
                amount: .units(tx.toAmountRaw, of: .transactionCoin),
                counterparty: .pool(fields[1]),
                evidence: .memo
            )

        case "-":
            // ⚠️ Basis points are the THIRD field, not the last. A single-sided
            // withdrawal appends the asset — `-:POOL:BPS:ASSET` — and reading
            // the last field refused that entirely valid memo.
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

    /// The basis points a fractional memo carries.
    ///
    /// Refused rather than clamped when out of range: a memo asking for more
    /// than all of a position is not something to paper over with a
    /// plausible-looking fraction.
    private func fraction(_ field: String) -> DecodedAmount? {
        guard let bps = Int(field), bps > 0, bps <= 10_000 else { return nil }
        return .fraction(basisPoints: bps, of: .transactionCoin)
    }

    // MARK: - Wire type

    private func decodeWireType(_ tx: SignedTransactionContent) -> DecodedTransaction? {
        switch tx.transactionType {
        case .thorMerge:
            return DecodedTransaction(
                operation: .merge,
                amount: .units(tx.toAmountRaw, of: .transactionCoin),
                evidence: .wireTransactionType
            )
        case .thorUnmerge:
            return DecodedTransaction(operation: .unmerge, amount: .unstated, evidence: .wireTransactionType)
        default:
            return nil
        }
    }
}
