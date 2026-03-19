//
//  SolanaTransactionParser.swift
//  VultisigApp
//
//  Created by Claude on 21/01/2025.
//

import Foundation
import WalletCore

struct ParsedSolanaTransaction {
    let instructions: [ParsedInstruction]

    struct ParsedInstruction {
        let programId: String
        let programName: String?
        let instructionType: String?
        let accountsCount: Int
        let dataLength: Int
    }
}

enum SolanaTransactionParser {

    // Known Solana programs
    private static let knownPrograms: [String: String] = [
        "11111111111111111111111111111111": "System Program",
        "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA": "Token Program",
        "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb": "Token-2022 Program",
        "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL": "Associated Token Program",
        "ComputeBudget111111111111111111111111111111": "Compute Budget Program"
    ]

    static func parse(base64Transaction: String) throws -> ParsedSolanaTransaction {
        guard let txData = Data(base64Encoded: base64Transaction) else {
            throw SolanaParsingError.invalidBase64
        }

        // Use WalletCore's TransactionDecoder to parse the transaction
        let decodedData = TransactionDecoder.decode(coinType: .solana, encodedTx: txData)
        let decodingOutput = try SolanaDecodingTransactionOutput(serializedBytes: decodedData)

        guard decodingOutput.hasTransaction else {
            throw SolanaParsingError.invalidTransactionFormat
        }

        let transaction = decodingOutput.transaction

        // Extract instructions and account keys based on message type
        let instructions: [WalletCore.SolanaRawMessage.Instruction]
        let accountKeys: [String]

        switch transaction.message {
        case .v0(let v0Message):
            instructions = v0Message.instructions
            accountKeys = v0Message.accountKeys

        case .legacy(let legacyMessage):
            instructions = legacyMessage.instructions
            accountKeys = legacyMessage.accountKeys

        default:
            throw SolanaParsingError.invalidTransactionFormat
        }

        // Parse instructions
        let parsedInstructions = instructions.map { instruction -> ParsedSolanaTransaction.ParsedInstruction in
            let programIndex = Int(instruction.programID)
            let programId = programIndex < accountKeys.count ? accountKeys[programIndex] : "Unknown"
            let programName = getKnownProgramName(programId: programId)
            let instructionType = getInstructionType(programId: programId, instructionData: instruction.programData)

            return ParsedSolanaTransaction.ParsedInstruction(
                programId: programId,
                programName: programName,
                instructionType: instructionType,
                accountsCount: instruction.accounts.count,
                dataLength: instruction.programData.count
            )
        }

        return ParsedSolanaTransaction(
            instructions: parsedInstructions
        )
    }

    static func getKnownProgramName(programId: String) -> String? {
        return knownPrograms[programId]
    }

    private static func getInstructionType(programId: String, instructionData: Data) -> String? {
        guard !instructionData.isEmpty else { return nil }

        let discriminator = instructionData[0]

        // System Program
        if programId == "11111111111111111111111111111111" {
            switch discriminator {
            case 0: return "Create Account"
            case 2: return "Transfer"
            case 3: return "Assign"
            case 4: return "Create Account With Seed"
            case 9: return "Transfer With Seed"
            default: return "System (\(discriminator))"
            }
        }

        // Token Program
        if programId == "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA" {
            switch discriminator {
            case 0: return "Initialize Mint"
            case 1: return "Initialize Account"
            case 3: return "Transfer"
            case 7: return "Mint To"
            case 8: return "Burn"
            case 9: return "Close Account"
            case 12: return "Transfer Checked"
            default: return "Token (\(discriminator))"
            }
        }

        // Token-2022 Program (same discriminators as Token Program)
        if programId == "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb" {
            switch discriminator {
            case 0: return "Initialize Mint"
            case 1: return "Initialize Account"
            case 3: return "Transfer"
            case 7: return "Mint To"
            case 8: return "Burn"
            case 9: return "Close Account"
            case 12: return "Transfer Checked"
            default: return "Token-2022 (\(discriminator))"
            }
        }

        // Associated Token Program
        if programId == "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL" {
            return "Create Associated Token Account"
        }

        // Compute Budget Program
        if programId == "ComputeBudget111111111111111111111111111111" {
            switch discriminator {
            case 0: return "Request Heap Frame"
            case 1: return "Set Compute Unit Limit"
            case 2: return "Set Compute Unit Price"
            default: return "Compute Budget (\(discriminator))"
            }
        }

        return nil
    }
}

enum SolanaParsingError: Error, LocalizedError {
    case invalidBase64
    case invalidTransactionFormat
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidBase64:
            return "Invalid base64 transaction"
        case .invalidTransactionFormat:
            return "Invalid transaction format"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        }
    }
}
