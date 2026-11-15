//
//  KaminoSimulationFailureTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class KaminoSimulationFailureTests: XCTestCase {

    /// `Custom: 1` from the System program, raised through the farms program
    /// creating its user state: the wallet's SOL ran out.
    func testTheSystemProgramsShortfallLogIsSol() {
        let failure = KaminoSimulationFailure(
            failure: "{InstructionError: [2, {Custom: 1}]}",
            logs: [
                "Transfer: insufficient lamports 1663425, need 5323840",
                "Program 11111111111111111111111111111111 failed: custom program error: 0x1"
            ]
        )
        XCTAssertEqual(failure, .insufficientSol)
    }

    /// A wallet that never held SOL does not exist, so it cannot pay the fee.
    func testAPayerThatDoesNotExistIsSol() {
        XCTAssertEqual(KaminoSimulationFailure(failure: "AccountNotFound", logs: []), .insufficientSol)
    }

    /// A missing program is not a missing payer, though its name contains one.
    func testAMissingProgramIsNotSol() {
        XCTAssertEqual(KaminoSimulationFailure(failure: "ProgramAccountNotFound", logs: []), .other)
    }

    func testAFeeThePayerCannotCoverIsSol() {
        XCTAssertEqual(KaminoSimulationFailure(failure: "InsufficientFundsForFee", logs: []), .insufficientSol)
    }

    /// Leaving the payer between zero and its rent-exempt minimum is refused for
    /// account 0, the payer. The same error on another account is not the
    /// wallet's SOL.
    func testOnlyThePayersRentShortfallIsSol() {
        XCTAssertEqual(
            KaminoSimulationFailure(failure: "{InsufficientFundsForRent: {account_index: 0}}", logs: []),
            .insufficientSol
        )
        XCTAssertEqual(
            KaminoSimulationFailure(failure: "{InsufficientFundsForRent: {account_index: 3}}", logs: []),
            .other
        )
    }

    /// The same `Custom: 1`, raised by the Token program inside the vault
    /// deposit, is the token balance, not SOL.
    func testTheTokenProgramsCodeOneIsTheToken() {
        let failure = KaminoSimulationFailure(
            failure: "{InstructionError: [1, {Custom: 1}]}",
            logs: [
                "Program TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA failed: custom program error: 0x1",
                "Program KvauGMspG5k6rtzrqqn7WNn3oZdyKqLKwK2XWQ8FLjd failed: custom program error: 0x1"
            ]
        )
        XCTAssertEqual(failure, .insufficientToken)
    }

    func testEverythingElseKeepsTheRuntimesOwnReason() {
        XCTAssertEqual(
            KaminoSimulationFailure(
                failure: "{InstructionError: [5, ProgramFailedToComplete]}",
                logs: ["Program FarmsPZpWu9i7Kky8tPN37rs2TpmMrAZrC7S7vJa91Hr failed: exceeded CUs meter at BPF instruction"]
            ),
            .other
        )
        XCTAssertEqual(KaminoSimulationFailure(failure: "{InstructionError: [1, {Custom: 6003}]}", logs: []), .other)
    }
}
