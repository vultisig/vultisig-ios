//
//  MayaChainTransactionDecoder.swift
//  VultisigApp
//
//  Decodes MAYAChain pool and node memos. It precedes the chain-agnostic
//  THORChain grammar because their shared heads use different field layouts.
//

import BigInt
import Foundation

struct MayaChainTransactionDecoder: TransactionContentDecoder {

    let handles: Set<Chain>? = [.mayaChain]

    /// Earlier approve or swap routes make the memo inert.
    private static let precedence: MemoPrecedence = .memoIsInertWhenRoutedEarlier

    func decode(_ tx: SignedTransactionContent) -> DecodedTransaction? {
        guard let content = tx.corroborated else { return nil }
        guard let memo = content.memo(Self.precedence) else { return nil }

        let fields = memo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard let head = fields.first else { return nil }

        switch head.uppercased() {
        case "POOL+":
            return DecodedTransaction(
                operation: .stake,
                amount: Self.carried(content.amount),
                evidence: .memo
            )

        case "POOL-":
            // Field 1 is basis points; later fields may name a single-sided asset.
            guard fields.count > 1, let bps = Int(fields[1]), bps > 0, bps <= 10_000 else {
                return nil
            }
            return DecodedTransaction(
                operation: .unstake,
                amount: .fraction(basisPoints: bps, of: .transactionCoin),
                evidence: .memo
            )

        // `BOND:<asset>:<units>:<node>`
        case "BOND":
            guard fields.count > 3, !fields[3].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .bond,
                amount: Self.lpUnits(from: fields),
                counterparty: .node(fields[3]),
                evidence: .memo
            )

        case "UNBOND":
            guard fields.count > 3, !fields[3].isEmpty else { return nil }
            return DecodedTransaction(
                operation: .unbond,
                amount: Self.lpUnits(from: fields),
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
    /// LP units are not asset base units, so they cannot use a currency amount.
    private static func lpUnits(from fields: [String]) -> DecodedAmount {
        // A future presentation needs an explicit "LP units of pool" model.
        _ = fields
        return .unstated
    }

    private static func carried(_ signed: SignedAmount) -> DecodedAmount {
        switch signed {
        case .committed(let raw) where raw > 0: return .units(raw, of: .transactionCoin)
        case .committed, .computedAtSigning: return .unstated
        }
    }

}
