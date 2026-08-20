//
//  CosmosTransactionDecoder.swift
//  VultisigApp
//
//  Reads Cosmos operations represented by an active memo or wire discriminator.
//  SignDoc-contained operations are handled by `CosmosSignDocDecoder` first.
//

import BigInt
import Foundation

struct CosmosTransactionDecoder: TransactionContentDecoder {

    let handles: Set<Chain>? = [.gaiaChain, .kujira, .osmosis, .noble, .akash, .dydx]

    /// Earlier approve or swap routes make the memo inert.
    private static let precedence: MemoPrecedence = .memoIsInertWhenRoutedEarlier

    func decode(_ tx: SignedTransactionContent) -> DecodedTransaction? {
        guard let content = tx.corroborated else { return nil }
        if let memo = content.memo(Self.precedence), let decoded = decodeMemo(memo, content: content) {
            return decoded
        }
        return decodeWireType(content)
    }

    private func decodeMemo(_ memo: String, content: CorroboratedContent) -> DecodedTransaction? {
        let fields = memo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let head = fields.first else { return nil }

        // Match the chain's case-insensitive heads.
        switch head.uppercased() {
        // `SWITCH` moves the asset to the sender's THORChain address.
        case "SWITCH":
            guard fields.count > 1, !fields[1].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .switchChain,
                amount: Self.carried(content.amount),
                evidence: .memo
            )

        // Governance votes move no quantity.
        case "DYDX_VOTE":
            guard fields.count > 2, !fields[2].isEmpty else { return nil }
            return DecodedTransaction(operation: .vote, amount: .unstated, evidence: .memo)

        default:
            return nil
        }
    }

    private func decodeWireType(_ content: CorroboratedContent) -> DecodedTransaction? {
        switch content.transactionType {
        case .ibcTransfer:
            return DecodedTransaction(
                operation: .ibcTransfer,
                amount: Self.carried(content.amount),
                evidence: .wireTransactionType
            )
        case .vote:
            return DecodedTransaction(operation: .vote, amount: .unstated, evidence: .wireTransactionType)
        default:
            return nil
        }
    }
    /// What the transaction carries, when it carries a figure at all.
    private static func carried(_ signed: SignedAmount) -> DecodedAmount {
        switch signed {
        case .committed(let raw) where raw > 0:
            return .units(raw, of: .transactionCoin)
        case .committed, .computedAtSigning:
            return .unstated
        }
    }

}
