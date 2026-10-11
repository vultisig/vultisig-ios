//
//  SolanaRawComputeBudgetCeilingTests.swift
//  VultisigAppTests
//
//  A raw dApp transaction carries its own ComputeBudget instructions and never
//  goes through the structured input builder, so the same priority-fee ceilings
//  are enforced on its bytes, in legacy and v0 messages, both when the pre-image
//  is derived and again at the signature splice.
//

@testable import VultisigApp
import BigInt
import XCTest

final class SolanaRawComputeBudgetCeilingTests: XCTestCase {

    private static let feePayer = Data(repeating: 0x11, count: 32)
    private static let computeBudgetProgram = Data(
        hexString: "0306466fe5211732ffecadba72c39be7bc8ce5bbc5f7126b2c439b3a40000000"
    )!
    private static let otherProgram = Data(repeating: 0x33, count: 32)
    private var vaultHexKey: String { Self.feePayer.hexString }

    // MARK: - Accepted

    func testNoComputeBudgetInstructionIsAccepted() throws {
        XCTAssertNoThrow(try preImage(of: transaction(instructions: [])))
    }

    func testComputeBudgetAtTheCeilingsIsAccepted() throws {
        let tx = transaction(instructions: [
            setLimit(UInt32(SolanaHelper.maxComputeUnitLimit)),
            setPrice(UInt64(SolanaHelper.maxPriorityFeePrice))
        ])
        XCTAssertNoThrow(try preImage(of: tx))
    }

    func testV0ComputeBudgetAtTheCeilingsIsAccepted() throws {
        let tx = transaction(version: .v0, instructions: [
            setLimit(UInt32(SolanaHelper.maxComputeUnitLimit)),
            setPrice(UInt64(SolanaHelper.maxPriorityFeePrice))
        ])
        XCTAssertNoThrow(try preImage(of: tx))
    }

    // MARK: - Refused

    func testInflatedPriceIsRefused() {
        let tx = transaction(instructions: [
            setLimit(100_000),
            setPrice(UInt64(SolanaHelper.maxPriorityFeePrice) + 1)
        ])
        XCTAssertThrowsError(try preImage(of: tx)) { assertMentions($0, "priority-fee price") }
    }

    func testInflatedLimitIsRefused() {
        let tx = transaction(instructions: [
            setLimit(UInt32(SolanaHelper.maxComputeUnitLimit) + 1),
            setPrice(1_000_000)
        ])
        XCTAssertThrowsError(try preImage(of: tx)) { assertMentions($0, "compute-unit limit") }
    }

    func testInflatedPriceInAV0MessageIsRefused() {
        let tx = transaction(version: .v0, instructions: [setPrice(UInt64.max)])
        XCTAssertThrowsError(try preImage(of: tx)) { assertMentions($0, "priority-fee price") }
    }

    func testEveryDuplicateInstructionIsChecked() {
        let tx = transaction(instructions: [
            setPrice(1_000_000),
            setPrice(UInt64(SolanaHelper.maxPriorityFeePrice) + 1)
        ])
        XCTAssertThrowsError(try preImage(of: tx)) { assertMentions($0, "priority-fee price") }
    }

    func testTruncatedInstructionDataIsRefused() {
        var tx = transaction(instructions: [setPrice(1)])
        tx.removeLast(3)
        XCTAssertThrowsError(try preImage(of: tx))
    }

    func testInstructionOutsideTheStaticKeysIsRefused() {
        let tx = transaction(instructions: [Instruction(programIndex: 9, data: [3] + le(1, 8))])
        XCTAssertThrowsError(try preImage(of: tx))
    }

    func testAnotherProgramsDataIsNotTreatedAsComputeBudget() throws {
        let tx = transaction(instructions: [
            Instruction(programIndex: 2, data: [3] + le(UInt64.max, 8))
        ])
        XCTAssertNoThrow(try preImage(of: tx))
    }

    func testSigningSpliceRefusesAnInflatedTransaction() {
        let tx = transaction(instructions: [setPrice(UInt64(SolanaHelper.maxPriorityFeePrice) + 1)])
        XCTAssertThrowsError(
            try SolanaHelper.signRawTransaction(
                coinHexPubKey: vaultHexKey,
                base64Transaction: tx.base64EncodedString(),
                signatures: [:]
            )
        ) { assertMentions($0, "priority-fee price") }
    }

    // MARK: - Helpers

    private struct Instruction {
        let programIndex: UInt8
        let data: [UInt8]
    }

    private enum Version { case legacy, v0 }

    private func setLimit(_ limit: UInt32) -> Instruction {
        Instruction(programIndex: 1, data: [2] + le(UInt64(limit), 4))
    }

    private func setPrice(_ price: UInt64) -> Instruction {
        Instruction(programIndex: 1, data: [3] + le(price, 8))
    }

    private func le(_ value: UInt64, _ length: Int) -> [UInt8] {
        (0..<length).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64($0))) }
    }

    /// One signer (the vault), the ComputeBudget program at index 1 and an
    /// unrelated program at index 2.
    private func transaction(version: Version = .legacy, instructions: [Instruction]) -> Data {
        var message = Data()
        if version == .v0 { message.append(0x80) }
        message.append(contentsOf: [1, 0, 2])
        message.append(3)
        message.append(Self.feePayer)
        message.append(Self.computeBudgetProgram)
        message.append(Self.otherProgram)
        message.append(Data(repeating: 0x22, count: 32))
        message.append(UInt8(instructions.count))
        for instruction in instructions {
            message.append(contentsOf: [instruction.programIndex, 0, UInt8(instruction.data.count)])
            message.append(contentsOf: instruction.data)
        }
        if version == .v0 { message.append(0) }
        return Data([1]) + Data(repeating: 0, count: 64) + message
    }

    private func preImage(of transaction: Data) throws -> [String] {
        try SolanaHelper.getPreSignedImageHashForRaw(
            coinHexPubKey: vaultHexKey,
            base64Transaction: transaction.base64EncodedString()
        )
    }

    private func assertMentions(_ error: Error, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue("\(error)".contains(text), "\(error)", file: file, line: line)
    }
}
