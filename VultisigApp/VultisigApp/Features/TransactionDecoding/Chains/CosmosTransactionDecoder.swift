//
//  CosmosTransactionDecoder.swift
//  VultisigApp
//
//  The Cosmos operations that announce themselves in a memo or on the wire.
//
//  ⚠️ **Deliberately partial, and the gap is the interesting part.** Cosmos
//  staking — delegate, undelegate, redelegate, claim rewards — and IBC transfers
//  carry NO memo. What identifies them is the message type URL inside the
//  SignDoc, so reading them needs `signedData`, which no decoder yet parses.
//  Those transactions therefore fall through to `.unknown` rather than being
//  guessed at from an address shape or an amount: a `signDirect` payload's
//  `toAmount` and `toAddress` can say anything at all without changing the
//  signature, so describing one from those fields would be describing something
//  other than what is about to be signed.
//
//  Chains are claimed only where a memo this decoder understands is actually
//  emitted. A chain whose only operations live in a SignDoc gains nothing from
//  being listed here and would only get a confident wrong answer sooner.
//

import BigInt
import Foundation

struct CosmosTransactionDecoder: TransactionContentDecoder {

    let handles: Set<Chain>? = [.gaiaChain, .kujira, .osmosis, .noble, .akash, .dydx]

    func decode(_ tx: SignedTransactionContent) -> DecodedTransaction? {
        if let memo = tx.signedMemo, let decoded = decodeMemo(memo, tx: tx) {
            return decoded
        }
        return decodeWireType(tx)
    }

    private func decodeMemo(_ memo: String, tx: SignedTransactionContent) -> DecodedTransaction? {
        let fields = memo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let head = fields.first else { return nil }

        switch head {
        // `SWITCH:<thorAddress>` moves a token to THORChain from the chain it
        // lives on now. It is not a send: the destination is the sender's own
        // THORChain address, and announcing it as a transfer to a stranger is
        // the reading this replaces.
        case "SWITCH":
            guard fields.count > 1, !fields[1].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .switchChain,
                amount: .units(tx.toAmountRaw, of: .transactionCoin),
                evidence: .memo
            )

        // `DYDX_VOTE:<option>:<proposalID>` moves nothing at all.
        case "DYDX_VOTE":
            guard fields.count > 2, !fields[2].isEmpty else { return nil }
            return DecodedTransaction(operation: .vote, amount: .unstated, evidence: .memo)

        default:
            return nil
        }
    }

    private func decodeWireType(_ tx: SignedTransactionContent) -> DecodedTransaction? {
        switch tx.transactionType {
        case .ibcTransfer:
            return DecodedTransaction(
                operation: .ibcTransfer,
                amount: .units(tx.toAmountRaw, of: .transactionCoin),
                evidence: .wireTransactionType
            )
        case .vote:
            return DecodedTransaction(operation: .vote, amount: .unstated, evidence: .wireTransactionType)
        default:
            return nil
        }
    }
}
