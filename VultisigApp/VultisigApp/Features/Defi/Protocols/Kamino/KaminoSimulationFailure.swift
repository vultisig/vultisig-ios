//
//  KaminoSimulationFailure.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Why a simulated Kamino transaction would fail, in the terms a user can act on.
///
/// Read from the runtime's own report rather than from instruction positions:
/// the same `Custom: 1` means "not enough SOL" when the System program raises it
/// and "not enough tokens" when the Token program does, and only the logs say
/// which program that was.
enum KaminoSimulationFailure: Equatable {
    case insufficientSol
    case insufficientToken
    case other

    init(failure: String, logs: [String]) {
        if Self.payerSolFailures.contains(failure)
            || logs.contains(where: { $0.hasPrefix(Self.systemTransferShortfallLog) }) {
            self = .insufficientSol
        } else if logs.contains(Self.tokenInsufficientFundsLog) {
            self = .insufficientToken
        } else {
            self = .other
        }
    }

    /// Matched whole: `ProgramAccountNotFound` is a missing program, and only account 0 is the payer.
    private static let payerSolFailures: Set<String> = [
        "AccountNotFound",
        "InsufficientFundsForFee",
        "{InsufficientFundsForRent: {account_index: 0}}"
    ]

    /// The System program's log when a transfer or account creation is short of lamports.
    private static let systemTransferShortfallLog = "Transfer: insufficient lamports"

    /// SPL Token's `InsufficientFunds`, code 1.
    private static let tokenInsufficientFundsLog =
        "Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA failed: custom program error: 0x1"
}

/// The SOL a refused deposit needed in total, against what the wallet holds.
///
/// Display only. The simulation is what refuses a transaction; this explains
/// the refusal and is never compared against a balance to make one.
struct KaminoSolShortfall: Equatable {
    let neededLamports: BigInt
    let availableLamports: BigInt

    var neededText: String { Self.solText(neededLamports) }
    var availableText: String { Self.solText(availableLamports) }

    private static func solText(_ lamports: BigInt) -> String {
        KaminoTokenAmount(baseUnits: lamports, decimals: solDecimals)
            .decimalValue
            .formatToDecimal(digits: displayDigits)
    }

    private static let solDecimals = 9
    /// Matches the eight places Windows shows for the same message.
    private static let displayDigits = 8
}
