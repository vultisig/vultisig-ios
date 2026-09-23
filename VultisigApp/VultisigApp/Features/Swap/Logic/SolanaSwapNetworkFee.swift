//
//  SolanaSwapNetworkFee.swift
//  VultisigApp
//

import BigInt
import Foundation

/// The fee charged by the network for a swap's signed Solana transaction.
/// ATA rent is a separate account deposit: an idempotent ATA instruction may
/// create nothing, and its payer need not be this vault.
enum SolanaSwapNetworkFee {
    private static let lamportsPerSignature = BigInt(5_000)
    private static let microLamportsPerLamport = BigInt(1_000_000)
    private static let defaultInstructionLimit = 200_000
    private static let defaultBuiltinLimit = 3_000

    static func fee(chainSpecific: BlockChainSpecific, transactionData: String? = nil) -> BigInt? {
        guard case let .Solana(_, price, limit, _, _, _) = chainSpecific else { return nil }
        if let transactionData, let wireFee = fee(transactionData: transactionData) {
            return wireFee
        }
        let priority = price > 0 && limit > 0
            ? (price * limit + microLamportsPerLamport - 1) / microLamportsPerLamport
            : .zero
        return lamportsPerSignature + priority
    }

    /// Read the fee from the bytes that the swap actually signs. Quote metadata
    /// can describe a different priority price/limit than these instructions.
    static func fee(transactionData: String) -> BigInt? {
        guard let transaction = try? SolanaV0Transaction(base64Transaction: transactionData) else {
            return nil
        }
        var price = BigInt.zero
        var explicitLimit: Int?
        var defaultLimit = 0

        for instruction in transaction.instructions {
            let program = transaction.staticAccountAddresses[Int(instruction.programIdIndex)]
            if program == SolanaV0Transaction.computeBudgetProgramId {
                switch instruction.data.first {
                case 2 where instruction.data.count == 5:
                    explicitLimit = instruction.data.dropFirst().enumerated().reduce(0) {
                        $0 | (Int($1.element) << ($1.offset * 8))
                    }
                case 3 where instruction.data.count == 9:
                    price = instruction.data.dropFirst().reversed().reduce(BigInt.zero) {
                        $0 * 256 + BigInt($1)
                    }
                default:
                    break
                }
            } else {
                // The runtime allocates 3K CUs to native System instructions
                // and 200K to the SBF programs used by swap routes.
                defaultLimit += program == "11111111111111111111111111111111"
                    ? defaultBuiltinLimit : defaultInstructionLimit
            }
        }

        let limit = min(explicitLimit ?? defaultLimit, Int(SolanaV0Transaction.maxComputeUnitLimit))
        let priority = price > 0
            ? (price * BigInt(limit) + microLamportsPerLamport - 1) / microLamportsPerLamport
            : .zero
        return BigInt(Int(transaction.numRequiredSignatures)) * lamportsPerSignature + priority
    }
}
