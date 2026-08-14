//
//  MayaChainTransactionDecoder.swift
//  VultisigApp
//
//  MAYAChain speaks the same family of memos as THORChain, one prefix apart,
//  and shares the property that matters: `POOL-:<bps>` names a FRACTION of a
//  position, not a quantity, over a transaction whose own amount is zero.
//
//  ⚠️ **Asked BEFORE the THORChain decoder, and scoped to MAYAChain.** The two
//  protocols spell `BOND`, `UNBOND` and `LEAVE` identically but put the node in
//  different fields — `BOND:<node>` against `BOND:<asset>:<fee>:<node>`. Since
//  the THORChain grammar deliberately applies to any chain, the narrower
//  decoder has to answer first or a MAYAChain bond would be read with the wrong
//  field layout and name an asset where a node belongs.
//

import BigInt
import Foundation

struct MayaChainTransactionDecoder: TransactionContentDecoder {

    let handles: Set<Chain>? = [.mayaChain]

    func decode(_ tx: SignedTransactionContent) -> DecodedTransaction? {
        guard let memo = tx.signedMemo else { return nil }

        let fields = memo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let head = fields.first else { return nil }

        switch head.uppercased() {
        case "POOL+":
            return DecodedTransaction(
                operation: .stake,
                amount: .units(tx.toAmountRaw, of: .transactionCoin),
                evidence: .memo
            )

        case "POOL-":
            // Same shape as `tcy-:<bps>`: ten-thousandths of whatever is staked
            // when the chain executes it, over a zero-amount deposit. Read from
            // the field it occupies rather than the last one, since a
            // single-sided withdrawal appends the asset after it.
            guard fields.count > 1, let bps = Int(fields[1]), bps > 0, bps <= 10_000 else {
                return nil
            }
            return DecodedTransaction(
                operation: .unstake,
                amount: .fraction(basisPoints: bps, of: .transactionCoin),
                evidence: .memo
            )

        // `BOND:<asset>:<units>:<node>` — the node is the FOURTH field.
        //
        // ⚠️ The amount is deliberately unstated. What is bonded is a quantity
        // of `<asset>`, and the transaction's own amount is a fixed CACAO
        // carrier that has nothing to do with it; the two emitters of this memo
        // disagree about whether the middle field is LP units or a fee, so
        // naming either as the bonded quantity would be a guess.
        case "BOND":
            guard fields.count > 3, !fields[3].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .bond,
                amount: .unstated,
                counterparty: .node(fields[3]),
                evidence: .memo
            )

        case "UNBOND":
            guard fields.count > 3, !fields[3].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .unbond,
                amount: .unstated,
                counterparty: .node(fields[3]),
                evidence: .memo
            )

        case "LEAVE":
            guard fields.count > 1, !fields[1].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .leave,
                amount: .unstated,
                counterparty: .node(fields[1]),
                evidence: .memo
            )

        default:
            return nil
        }
    }
}
