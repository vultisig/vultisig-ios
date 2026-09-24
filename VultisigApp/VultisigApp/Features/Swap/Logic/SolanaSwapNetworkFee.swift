//
//  SolanaSwapNetworkFee.swift
//  VultisigApp
//

import BigInt
import Foundation

protocol SolanaSwapAccountFetching: SolanaAddressLookupTableFetching {
    func checkAccountExists(address: String) async throws -> (exists: Bool, isToken2022: Bool)
    func fetchRentExemptMinimum(size: Int) async throws -> UInt64
}

extension SolanaService: SolanaSwapAccountFetching {}

enum SolanaSwapAtaRentState: Equatable {
    case notRequired
    case loading
    case resolved(BigInt)
    case failed

    var amount: BigInt? {
        switch self {
        case .notRequired: .zero
        case let .resolved(rent): rent
        case .loading, .failed: nil
        }
    }
}

/// The displayed cost of a swap's signed Solana transaction. ATA rent is an
/// account deposit, included only when the vault pays to create an account.
enum SolanaSwapNetworkFee {
    private static let lamportsPerSignature = BigInt(5_000)
    private static let microLamportsPerLamport = BigInt(1_000_000)
    private static let defaultInstructionLimit = 200_000
    private static let defaultBuiltinLimit = 3_000

    static func fee(
        chainSpecific: BlockChainSpecific,
        transactionData: String? = nil,
        ataRent: BigInt = .zero
    ) -> BigInt? {
        guard case let .Solana(_, price, limit, _, _, _) = chainSpecific else { return nil }
        if let transactionData, let wireFee = fee(transactionData: transactionData, ataRent: ataRent) {
            return wireFee
        }
        let priority = price > 0 && limit > 0
            ? (price * limit + microLamportsPerLamport - 1) / microLamportsPerLamport
            : .zero
        return lamportsPerSignature + priority + ataRent
    }

    /// Read the fee from the bytes that the swap actually signs. Quote metadata
    /// can describe a different priority price/limit than these instructions.
    static func fee(transactionData: String, ataRent: BigInt = .zero) -> BigInt? {
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
        return BigInt(Int(transaction.numRequiredSignatures)) * lamportsPerSignature + priority + ataRent
    }

    static func transactionData(quote: SwapQuote?) -> String? {
        switch quote {
        case let .jupiter(quote, _, _, _):
            return quote.tx.data
        case let .swapkit(response, _, _):
            if case let .solana(data) = response.tx { return data }
            return nil
        default:
            return nil
        }
    }

    static func transactionData(payload: KeysignPayload?) -> String? {
        guard case let .generic(swap)? = payload?.swapPayload,
              case .Solana = payload?.chainSpecific else { return nil }
        return swap.quote.tx.data
    }

    /// Check idempotent creation against current chain state. A plain Create
    /// must create its ATA for the transaction to succeed. Other payers fund
    /// their own ATA, so neither device charges that deposit to this vault.
    static func ataRent(
        transactionData: String,
        accounts: SolanaSwapAccountFetching = SolanaService.shared
    ) async throws -> BigInt {
        let transaction = try SolanaV0Transaction(base64Transaction: transactionData)
        let staticAddresses = transaction.staticAccountAddresses
        let creations = transaction.instructions.filter { instruction in
            staticAddresses[Int(instruction.programIdIndex)] == SolanaAssociatedTokenAccount.programId
                && instruction.accountIndexes.count >= 6
                && instruction.accountIndexes[0] == 0
                && (instruction.data.isEmpty || instruction.data == [0] || instruction.data == [1])
        }
        guard !creations.isEmpty else { return .zero }
        let needsLookup = creations.contains { instruction in
            Int(instruction.accountIndexes[1]) >= staticAddresses.count
                || Int(instruction.accountIndexes[5]) >= staticAddresses.count
        }
        let addresses: [String]
        if needsLookup {
            let tables = try await accounts.fetchAddressLookupTables(
                addresses: transaction.addressTableLookups.map(\.tableAddress)
            )
            addresses = try transaction.resolvedAccountAddresses(lookupTables: tables)
        } else {
            addresses = staticAddresses
        }
        var seen = Set<String>()
        var rent = BigInt.zero

        for instruction in creations {
            let ata = addresses[Int(instruction.accountIndexes[1])]
            guard seen.insert(ata).inserted else { continue }
            let tokenProgramAddress = addresses[Int(instruction.accountIndexes[5])]
            guard let tokenProgram = SolanaTokenProgram(programId: tokenProgramAddress) else { continue }
            if instruction.data == [1], try await accounts.checkAccountExists(address: ata).exists {
                continue
            }
            let size = tokenProgram == .token2022 ? 170 : 165
            rent += BigInt(try await accounts.fetchRentExemptMinimum(size: size))
        }
        return rent
    }
}
