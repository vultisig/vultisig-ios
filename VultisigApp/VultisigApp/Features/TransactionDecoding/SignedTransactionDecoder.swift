//
//  SignedTransactionDecoder.swift
//  VultisigApp
//
//  Reads operations from content that will actually be signed. Unclaimed
//  transactions remain `.unknown` and preserve existing presentation.
//

import Foundation

/// A reader for one chain family's signed grammar. `handles == nil` requires
/// the reader to establish provenance from the transaction itself.
protocol TransactionContentDecoder {

    /// The chains this decoder's grammar is meaningful on, or `nil` for one
    /// that establishes its own provenance from the transaction.
    var handles: Set<Chain>? { get }

    func decode(_ tx: SignedTransactionContent) -> DecodedTransaction?
}

enum SignedTransactionDecoder {

    /// Registered readers in precedence order.
    static let decoders: [TransactionContentDecoder] = [
        SolanaTransactionDecoder(),
        TronTransactionDecoder(),
        TonTransactionDecoder()
    ]

    /// Returns `.unknown` when no reader can prove an operation.
    static func decode(_ tx: SignedTransactionContent) -> DecodedTransaction {
        for decoder in decoders where decoder.handles?.contains(tx.chain) ?? true {
            if let decoded = decoder.decode(tx) {
                return decoded
            }
        }

        return .unreadable
    }
}
