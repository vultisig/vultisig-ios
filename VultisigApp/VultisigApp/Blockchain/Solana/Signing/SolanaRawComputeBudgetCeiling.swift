//
//  SolanaRawComputeBudgetCeiling.swift
//  VultisigApp
//

import BigInt
import Foundation

extension SolanaHelper {

    /// Holds a raw dApp transaction's ComputeBudget instructions to the same
    /// ceilings as the structured input builder. The raw path hashes the message
    /// verbatim and never reaches `getPreSignedInputData`, so without this a
    /// compromised initiator could have the vault sign an arbitrary priority fee
    /// inside the relayed bytes. Every duplicate instruction is checked, and a
    /// message that cannot be parsed is refused rather than skipped. A
    /// transaction without these instructions pays no priority fee and passes.
    static func requireRawComputeBudgetWithinCeiling(message: Data) throws {
        for data in try computeBudgetInstructionData(ofMessage: message) {
            switch data.first {
            case ComputeBudgetInstruction.setUnitLimit:
                guard littleEndianUInt(data, offset: 1, length: 4) <= maxComputeUnitLimit else {
                    throw HelperError.runtimeError(
                        "Solana raw transaction sets a compute-unit limit above the \(maxComputeUnitLimit) ceiling"
                    )
                }
            case ComputeBudgetInstruction.setUnitPrice:
                guard littleEndianUInt(data, offset: 1, length: 8) <= maxPriorityFeePrice else {
                    throw HelperError.runtimeError(
                        "Solana raw transaction sets a priority-fee price above the \(maxPriorityFeePrice) ceiling"
                    )
                }
            default:
                break
            }
        }
    }

    /// Data of every instruction in a legacy or v0 message whose program is the
    /// ComputeBudget program, in message order. A program id is always a static
    /// account key (the runtime refuses to invoke a program loaded through a
    /// lookup table), so the static keys are enough to recognise it.
    private static func computeBudgetInstructionData(ofMessage message: Data) throws -> [[UInt8]] {
        let bytes = [UInt8](message)
        var offset = 0
        if let first = bytes.first, first & 0x80 != 0 {
            guard first & 0x7F == 0 else {
                throw HelperError.runtimeError("Unsupported Solana message version \(first & 0x7F)")
            }
            offset = 1
        }
        guard bytes.count >= offset + 3 else {
            throw HelperError.runtimeError("Solana message too short for header")
        }
        offset += 3

        let keyCount = try readCompactLength(bytes, offset: &offset)
        let keysStart = offset
        guard bytes.count >= keysStart + keyCount * 32 + 32 else {
            throw HelperError.runtimeError("Solana message too short for its account keys and blockhash")
        }
        offset = keysStart + keyCount * 32 + 32

        let instructionCount = try readCompactLength(bytes, offset: &offset)
        var matches: [[UInt8]] = []
        for _ in 0..<instructionCount {
            guard offset < bytes.count else {
                throw HelperError.runtimeError("Solana message too short for its instructions")
            }
            let programIndex = Int(bytes[offset])
            offset += 1
            guard programIndex < keyCount else {
                throw HelperError.runtimeError(
                    "Solana instruction references program index \(programIndex) outside its \(keyCount) static account key(s)"
                )
            }
            let accountCount = try readCompactLength(bytes, offset: &offset)
            offset += accountCount
            let dataLength = try readCompactLength(bytes, offset: &offset)
            guard offset + dataLength <= bytes.count else {
                throw HelperError.runtimeError("Solana message too short for its instruction data")
            }
            let keyStart = keysStart + programIndex * 32
            if Array(bytes[keyStart..<(keyStart + 32)]) == SolanaV0Transaction.computeBudgetProgramKey {
                matches.append(Array(bytes[offset..<(offset + dataLength)]))
            }
            offset += dataLength
        }
        return matches
    }

    private static func readCompactLength(_ bytes: [UInt8], offset: inout Int) throws -> Int {
        guard offset < bytes.count else {
            throw HelperError.runtimeError("Solana message too short for a length prefix")
        }
        let (value, byteCount) = try SolanaV0Transaction.decodeCompactLength(bytes[offset...])
        offset += byteCount
        return value
    }

    /// Little-endian unsigned integer of `length` bytes at `offset`; zero when
    /// the data is too short, as the instruction would then not carry a value.
    private static func littleEndianUInt(_ data: [UInt8], offset: Int, length: Int) -> BigInt {
        guard offset + length <= data.count else { return .zero }
        return data[offset..<(offset + length)].reversed().reduce(BigInt.zero) { $0 << 8 | BigInt($1) }
    }
}
