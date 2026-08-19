//
//  TronTransactionDecoder.swift
//  VultisigApp
//
//  Decodes TRON resource staking from the memo and amount consumed by the
//  signer. Typed dApp contracts outrank that memo in `SignedTransactionContent`.
//

import BigInt
import Foundation

struct TronTransactionDecoder: TransactionContentDecoder {

    /// The memo grammar is meaningful only on TRON.
    var handles: Set<Chain>? { [.tron] }

    private static let freeze = "FREEZE:"
    private static let unfreeze = "UNFREEZE:"

    /// Exact resource names accepted by the signer.
    private static let resources: Set<String> = ["BANDWIDTH", "ENERGY"]

    func decode(_ tx: SignedTransactionContent) -> DecodedTransaction? {
        // Approve and swap routes make this sidecar memo inert.
        guard let content = tx.corroborated,
              let memo = content.memo(.memoIsInertWhenRoutedEarlier) else { return nil }

        let operation: DecodedOperation
        let resource: String

        if memo.hasPrefix(Self.freeze) {
            operation = .stake
            resource = String(memo.dropFirst(Self.freeze.count))
        } else if memo.hasPrefix(Self.unfreeze) {
            operation = .unstake
            resource = String(memo.dropFirst(Self.unfreeze.count))
        } else {
            return nil
        }

        // Match the signer's case-sensitive validation.
        guard Self.resources.contains(resource) else { return nil }

        return DecodedTransaction(
            operation: operation,
            amount: Self.amount(from: content.amount),
            counterparty: nil,
            evidence: .memo
        )
    }

    /// Freeze instructions always move chain-native TRX, independent of payload
    /// display metadata. Only positive, encodable committed amounts are stated.
    private static func amount(from signed: SignedAmount) -> DecodedAmount {
        switch signed {
        case .committed(let raw) where raw > 0 && raw <= BigInt(Int64.max):
            return .units(raw, of: .chainNative)
        case .committed, .computedAtSigning:
            return .unstated
        }
    }
}
