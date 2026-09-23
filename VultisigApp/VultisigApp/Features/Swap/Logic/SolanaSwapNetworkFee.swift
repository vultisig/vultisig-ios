//
//  SolanaSwapNetworkFee.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Display fee for a Solana swap. The generic swap signs the quote's wire
/// transaction, so its signature and ATA counts come from those bytes rather
/// than the transfer-oriented `chainSpecific.gas` estimate.
enum SolanaSwapNetworkFee {
    private static let lamportsPerSignature = BigInt(5_000)
    private static let microLamportsPerLamport = BigInt(1_000_000)

    static func fee(chainSpecific: BlockChainSpecific, transactionData: String? = nil) -> BigInt? {
        guard case let .Solana(_, price, limit, _, _, _) = chainSpecific else { return nil }

        let transaction = transactionData.flatMap { try? SolanaV0Transaction(base64Transaction: $0) }
        let signatures = BigInt(transaction.map { Int($0.numRequiredSignatures) } ?? 1)
        let priority = price > 0 && limit > 0
            ? (price * limit + microLamportsPerLamport - 1) / microLamportsPerLamport
            : .zero
        let ataRent = BigInt(ataCreationCount(in: transaction)) * SolanaHelper.ataRentLamports
        return signatures * lamportsPerSignature + priority + ataRent
    }

    /// Extra wire costs beyond the one-signature fee computed before the quote
    /// reaches the initiator's display model.
    static func additionalWireFee(transactionData: String) -> BigInt {
        guard let transaction = try? SolanaV0Transaction(base64Transaction: transactionData) else {
            return .zero
        }
        let extraSignatures = max(0, Int(transaction.numRequiredSignatures) - 1)
        return BigInt(extraSignatures) * lamportsPerSignature
            + BigInt(ataCreationCount(in: transaction)) * SolanaHelper.ataRentLamports
    }

    private static func ataCreationCount(in transaction: SolanaV0Transaction?) -> Int {
        guard let transaction else { return 0 }
        let accounts = transaction.staticAccountAddresses
        return transaction.instructions.filter { instruction in
            accounts[Int(instruction.programIdIndex)] == SolanaAssociatedTokenAccount.programId
                && (instruction.data.isEmpty || instruction.data.first == 1)
        }.count
    }
}
