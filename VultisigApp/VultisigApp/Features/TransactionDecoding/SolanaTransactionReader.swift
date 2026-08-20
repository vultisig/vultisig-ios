//
//  SolanaTransactionReader.swift
//  VultisigApp
//
//  Reads self-contained Solana staking transactions from the bytes co-signers
//  receive. Address-table lookups and partial/malformed messages are refused;
//  every untrusted length and index is bounded.
//

import BigInt
import Foundation
import WalletCore

enum SolanaTransactionReader {

    struct Reading: Hashable {
        let operation: DecodedOperation
        let amount: DecodedAmount
        let counterparty: DecodedCounterparty?
    }

    /// The System Program funds new stake accounts.
    private static let systemProgramID: Data? = Base58.decodeNoCheck(
        string: "11111111111111111111111111111111"
    )

    /// Compute-budget instructions may accompany staking without moving value.
    private static let computeBudgetProgramID: Data? = Base58.decodeNoCheck(
        string: "ComputeBudget111111111111111111111111111111"
    )

    private static let stakeProgramID: Data? = Base58.decodeNoCheck(
        string: "Stake11111111111111111111111111111111111111"
    )

    /// Little-endian stake-program discriminators.
    private enum StakeInstruction: UInt32 {
        case initialize = 0
        case authorize = 1
        case delegate = 2
        case split = 3
        case withdraw = 4
        case deactivate = 5
    }

    // MARK: - Refusal limits

    private static let maximumTransactionBytes = 8 * 1024
    private static let maximumAccounts = 128
    private static let maximumInstructions = 32

    // MARK: - Reading

    /// Reads one complete relayed transaction or refuses it.
    static func read(base64 encoded: String) -> Reading? {
        guard encoded.utf8.count <= maximumTransactionBytes * 2,
              let bytes = Data(base64Encoded: encoded),
              !bytes.isEmpty,
              bytes.count <= maximumTransactionBytes,
              let stakeProgramID,
              let computeBudgetProgramID,
              let systemProgramID
        else { return nil }

        var reader = ByteReader(bytes)

        // Signatures precede the message.
        guard let signatureCount = reader.readCompactU16(), signatureCount <= maximumAccounts,
              reader.skip(Int(signatureCount) * 64)
        else { return nil }

        // Only legacy and self-contained v0 messages are readable.
        guard let first = reader.peek() else { return nil }
        let isVersioned: Bool
        if first & 0x80 != 0 {
            guard first & 0x7F == 0, reader.skip(1) else { return nil }
            isVersioned = true
        } else {
            isVersioned = false
        }

        // Header: required signatures and readonly counts.
        guard reader.skip(3) else { return nil }

        guard let accountCount = reader.readCompactU16(), accountCount <= maximumAccounts else {
            return nil
        }
        var accounts: [Data] = []
        accounts.reserveCapacity(Int(accountCount))
        for _ in 0..<accountCount {
            guard let key = reader.read(32) else { return nil }
            accounts.append(key)
        }

        // Recent blockhash.
        guard reader.skip(32) else { return nil }

        guard let instructionCount = reader.readCompactU16(),
              instructionCount <= maximumInstructions
        else { return nil }

        // Preserve instruction order; ignore value-neutral compute-budget entries.
        var instructions: [(program: Data, accountIndexes: Data, data: Data)] = []

        for _ in 0..<instructionCount {
            guard let programIndex = reader.readByte(),
                  let accountIndexCount = reader.readCompactU16(),
                  accountIndexCount <= maximumAccounts,
                  let accountIndexes = reader.read(Int(accountIndexCount)),
                  let dataLength = reader.readCompactU16(),
                  let data = reader.read(Int(dataLength))
            else { return nil }

            guard Int(programIndex) < accounts.count else { return nil }
            let program = accounts[Int(programIndex)]

            if program == computeBudgetProgramID { continue }
            instructions.append((program, accountIndexes, data))
        }

        if isVersioned {
            // Non-empty address lookups require unavailable network state.
            guard reader.readCompactU16() == 0 else { return nil }
        }

        // Every signed byte must be accounted for.
        guard reader.remaining == 0 else { return nil }

        return read(sequence: instructions, accounts: accounts)
    }

    /// Matches complete instruction sequences so unrelated transfers cannot hide
    /// beside a recognized staking instruction.
    private static func read(
        sequence: [(program: Data, accountIndexes: Data, data: Data)],
        accounts: [Data]
    ) -> Reading? {
        func stakeInstruction(_ i: Int) -> StakeInstruction? {
            guard sequence.indices.contains(i), sequence[i].program == stakeProgramID else { return nil }
            return discriminator(of: sequence[i].data).flatMap(StakeInstruction.init(rawValue:))
        }

        switch sequence.count {
        case 1:
            // Deactivate and withdraw stand alone.
            guard let only = stakeInstruction(0), only != .delegate else { return nil }
            return read(instruction: sequence[0].data, accountIndexes: sequence[0].accountIndexes, accounts: accounts)

        case 3:
            // WalletCore delegation: create + initialize + delegate.
            guard let funding = createStakeAccountFunding(sequence[0], accounts: accounts),
                  isInitialize(sequence[1]),
                  isDelegate(sequence[2]),
                  let createdStake = accountIndex(at: 1, in: sequence[0].accountIndexes, accounts: accounts),
                  let initializedStake = accountIndex(at: 0, in: sequence[1].accountIndexes, accounts: accounts),
                  let delegatedStake = accountIndex(at: 0, in: sequence[2].accountIndexes, accounts: accounts),
                  createdStake == initializedStake,
                  initializedStake == delegatedStake,
                  let payer = accountIndex(at: 0, in: sequence[0].accountIndexes, accounts: accounts),
                  let authority = accountIndex(at: 5, in: sequence[2].accountIndexes, accounts: accounts),
                  payer == authority,
                  authorizedStaker(in: sequence[1].data) == accounts[authority]
            else { return nil }
            guard let vote = account(at: 1, in: sequence[2].accountIndexes, accounts: accounts) else {
                return nil
            }
            return Reading(
                operation: .delegate,
                amount: .accountFunding(BigInt(funding), of: .chainNative),
                counterparty: .validator(vote)
            )

        default:
            return nil
        }
    }

    /// Reads a four-byte little-endian discriminator.
    private static func discriminator(of data: Data) -> UInt32? {
        guard data.count >= 4 else { return nil }
        var value: UInt32 = 0
        for offset in 0..<4 {
            value |= UInt32(data[data.index(data.startIndex, offsetBy: offset)]) << (8 * UInt32(offset))
        }
        return value
    }

    private static func createStakeAccountFunding(
        _ instruction: (program: Data, accountIndexes: Data, data: Data),
        accounts: [Data]
    ) -> UInt64? {
        guard instruction.program == systemProgramID,
              let kind = discriminator(of: instruction.data),
              let stakeProgramID,
              let payer = accountIndex(at: 0, in: instruction.accountIndexes, accounts: accounts),
              let createdStake = accountIndex(at: 1, in: instruction.accountIndexes, accounts: accounts),
              payer != createdStake
        else { return nil }

        switch kind {
        case 0: // SystemInstruction::CreateAccount
            guard instruction.accountIndexes.count == 2,
                  instruction.data.count == 52,
                  let lamports = littleEndianUInt64(in: instruction.data, at: 4), lamports > 0,
                  littleEndianUInt64(in: instruction.data, at: 12) == 200
            else { return nil }
            return bytes(in: instruction.data, at: 20, count: 32) == stakeProgramID ? lamports : nil

        case 3: // SystemInstruction::CreateAccountWithSeed, emitted by WalletCore
            guard instruction.accountIndexes.count == 3,
                  let seedLength = littleEndianUInt64(in: instruction.data, at: 36),
                  seedLength <= 32,
                  seedLength <= UInt64(Int.max)
            else { return nil }

            let seedCount = Int(seedLength)
            let lamportsOffset = 44 + seedCount
            let spaceOffset = lamportsOffset + 8
            let ownerOffset = spaceOffset + 8
            guard instruction.data.count == ownerOffset + 32,
                  let lamports = littleEndianUInt64(in: instruction.data, at: lamportsOffset), lamports > 0,
                  littleEndianUInt64(in: instruction.data, at: spaceOffset) == 200,
                  bytes(in: instruction.data, at: ownerOffset, count: 32) == stakeProgramID,
                  let base = accountIndex(at: 2, in: instruction.accountIndexes, accounts: accounts),
                  base == payer,
                  bytes(in: instruction.data, at: 4, count: 32) == accounts[base]
            else { return nil }
            return lamports

        default:
            return nil
        }
    }

    private static func isInitialize(
        _ instruction: (program: Data, accountIndexes: Data, data: Data)
    ) -> Bool {
        instruction.program == stakeProgramID
            && instruction.accountIndexes.count == 2
            && instruction.data.count == 116
            && discriminator(of: instruction.data) == StakeInstruction.initialize.rawValue
    }

    private static func isDelegate(
        _ instruction: (program: Data, accountIndexes: Data, data: Data)
    ) -> Bool {
        instruction.program == stakeProgramID
            && instruction.accountIndexes.count == 6
            && instruction.data.count == 4
            && discriminator(of: instruction.data) == StakeInstruction.delegate.rawValue
    }

    private static func authorizedStaker(in initializeData: Data) -> Data? {
        guard initializeData.count == 116 else { return nil }
        let start = initializeData.index(initializeData.startIndex, offsetBy: 4)
        let end = initializeData.index(start, offsetBy: 32)
        return initializeData[start..<end]
    }

    /// One stake-program instruction.
    private static func read(
        instruction data: Data,
        accountIndexes: Data,
        accounts: [Data]
    ) -> Reading? {
        guard data.count >= 4 else { return nil }

        let start = data.startIndex
        var discriminator: UInt32 = 0
        for offset in 0..<4 {
            discriminator |= UInt32(data[data.index(start, offsetBy: offset)]) << (8 * UInt32(offset))
        }

        guard let instruction = StakeInstruction(rawValue: discriminator) else { return nil }

        switch instruction {
        case .delegate:
            // Funding includes rent reserve, so delegation states no amount.
            guard data.count == 4,
                  accountIndexes.count == 6,
                  let vote = account(at: 1, in: accountIndexes, accounts: accounts)
            else { return nil }
            return Reading(operation: .delegate, amount: .unstated, counterparty: .validator(vote))

        case .deactivate:
            // Deactivation cools the whole account and names no quantity.
            guard data.count == 4,
                  accountIndexes.count == 3,
                  let stake = account(at: 0, in: accountIndexes, accounts: accounts)
            else { return nil }
            return Reading(operation: .unstake, amount: .unstated, counterparty: .stakeAccount(stake))

        case .withdraw:
            // Withdraw data carries the lamports leaving the stake account.
            guard data.count == 12,
                  accountIndexes.count == 5,
                  let stake = account(at: 0, in: accountIndexes, accounts: accounts),
                  let lamports = littleEndianUInt64(in: data, at: 4)
            else { return nil }
            return Reading(
                operation: .withdrawStake,
                // Stake accounts hold chain-native SOL.
                amount: .units(BigInt(lamports), of: .chainNative),
                counterparty: .stakeAccount(stake)
            )

        // These instructions are not independently emitted by this app.
        case .initialize, .authorize, .split:
            return nil
        }
    }

    /// The base58 account an instruction references at `position`.
    private static func account(
        at position: Int,
        in indexes: Data,
        accounts: [Data]
    ) -> String? {
        guard position < indexes.count else { return nil }
        let index = Int(indexes[indexes.index(indexes.startIndex, offsetBy: position)])
        guard index < accounts.count else { return nil }
        return Base58.encodeNoCheck(data: accounts[index])
    }

    private static func accountIndex(
        at position: Int,
        in indexes: Data,
        accounts: [Data]
    ) -> Int? {
        guard position < indexes.count else { return nil }
        let index = Int(indexes[indexes.index(indexes.startIndex, offsetBy: position)])
        return index < accounts.count ? index : nil
    }

    private static func littleEndianUInt64(in data: Data, at offset: Int) -> UInt64? {
        guard data.count >= offset + 8 else { return nil }
        let start = data.index(data.startIndex, offsetBy: offset)

        var value: UInt64 = 0
        for byte in 0..<8 {
            value |= UInt64(data[data.index(start, offsetBy: byte)]) << (8 * UInt64(byte))
        }
        return value
    }

    private static func bytes(in data: Data, at offset: Int, count: Int) -> Data? {
        guard offset >= 0, count >= 0, data.count >= offset + count else { return nil }
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: count)
        return data[start..<end]
    }

    // MARK: - A bounds-checked walk

    /// Bounds-checked reader that also supports non-zero-index `Data` slices.
    private struct ByteReader {
        private let bytes: Data
        private var index: Data.Index

        init(_ bytes: Data) {
            self.bytes = bytes
            self.index = bytes.startIndex
        }

        var remaining: Int { bytes.distance(from: index, to: bytes.endIndex) }

        func peek() -> UInt8? {
            guard index < bytes.endIndex else { return nil }
            return bytes[index]
        }

        mutating func readByte() -> UInt8? {
            guard index < bytes.endIndex else { return nil }
            let byte = bytes[index]
            index = bytes.index(after: index)
            return byte
        }

        mutating func read(_ count: Int) -> Data? {
            guard count >= 0, remaining >= count else { return nil }
            let end = bytes.index(index, offsetBy: count)
            defer { index = end }
            return bytes[index..<end]
        }

        mutating func skip(_ count: Int) -> Bool {
            guard count >= 0, remaining >= count else { return false }
            index = bytes.index(index, offsetBy: count)
            return true
        }

        /// Solana shortvec, bounded by its three-byte UInt16 encoding.
        mutating func readCompactU16() -> UInt16? {
            var value: UInt32 = 0

            for round in 0..<3 {
                guard let byte = readByte() else { return nil }
                value |= UInt32(byte & 0x7F) << (7 * UInt32(round))
                if byte & 0x80 == 0 {
                    return value <= UInt32(UInt16.max) ? UInt16(value) : nil
                }
            }

            return nil
        }
    }
}
