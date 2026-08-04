//
//  SolanaTransactionParserComputeBudgetTests.swift
//  VultisigAppTests
//
//  `SolanaTransactionParser` feeds the keysign verify screen, so a mislabelled
//  instruction is a co-signer approving something other than what they read.
//  Its ComputeBudget decoder was off by one — discriminant 0 is the deprecated
//  `RequestUnits`, so the limit and price instructions are 2 and 3, not 1 and 2 —
//  which mislabelled every priority-fee instruction, including the ones the app
//  injects itself.
//

@testable import VultisigApp
import WalletCore
import XCTest

final class SolanaTransactionParserComputeBudgetTests: XCTestCase {

    private static let computeBudgetProgramId = "ComputeBudget111111111111111111111111111111"

    func testComputeBudgetDiscriminantsMatchTheOnChainEncoding() throws {
        let parsed = try SolanaTransactionParser.parse(base64Transaction: try Self.computeBudgetSample())

        XCTAssertEqual(parsed.instructions.count, 4)
        XCTAssertTrue(parsed.instructions.allSatisfy { $0.programId == Self.computeBudgetProgramId })
        XCTAssertTrue(parsed.instructions.allSatisfy { $0.programName == "Compute Budget Program" })

        XCTAssertEqual(parsed.instructions[0].instructionType, "Request Units (Deprecated)")
        XCTAssertEqual(parsed.instructions[1].instructionType, "Request Heap Frame")
        XCTAssertEqual(parsed.instructions[2].instructionType, "Set Compute Unit Limit")
        XCTAssertEqual(parsed.instructions[3].instructionType, "Set Compute Unit Price")
    }

    func testKaminoProgramsAreNamed() {
        XCTAssertEqual(
            SolanaTransactionParser.getKnownProgramName(programId: KaminoVaultRegistry.programId),
            "Kamino Vaults Program"
        )
        XCTAssertEqual(
            SolanaTransactionParser.getKnownProgramName(programId: KaminoVaultRegistry.farmsProgramId),
            "Kamino Farms Program"
        )
    }

    /// The discriminants the app writes have to be the ones the app reads back.
    func testInjectedInstructionsDecodeAsLimitAndPrice() throws {
        let injected = try SolanaV0Transaction(base64Transaction: KaminoTransactionFixtures.usdcDeposit.source)
            .injectingComputeBudget(
                price: KaminoTransactionFixtures.unitPriceMicroLamports,
                limit: KaminoComputeBudget.tokenDepositUnitLimit
            )

        XCTAssertEqual(injected.instructions[0].data.first, ComputeBudgetInstruction.setUnitLimit)
        XCTAssertEqual(injected.instructions[1].data.first, ComputeBudgetInstruction.setUnitPrice)

        let limit = try Self.singleInstructionSample(data: injected.instructions[0].data)
        let price = try Self.singleInstructionSample(data: injected.instructions[1].data)

        XCTAssertEqual(
            try SolanaTransactionParser.parse(base64Transaction: limit).instructions.first?.instructionType,
            "Set Compute Unit Limit"
        )
        XCTAssertEqual(
            try SolanaTransactionParser.parse(base64Transaction: price).instructions.first?.instructionType,
            "Set Compute Unit Price"
        )
    }

    // MARK: - Sample transactions

    /// A v0 transaction carrying one ComputeBudget instruction per discriminant,
    /// with no lookup tables — the parser only needs the program id and the first
    /// data byte, so this isolates the mapping under test.
    private static func computeBudgetSample() throws -> String {
        try sample(instructionData: [
            [ComputeBudgetInstruction.requestUnitsDeprecated, 0x40, 0x42, 0x0F, 0x00],
            [ComputeBudgetInstruction.requestHeapFrame, 0x00, 0x00, 0x04, 0x00],
            [ComputeBudgetInstruction.setUnitLimit, 0x00, 0xE2, 0x04, 0x00],
            [ComputeBudgetInstruction.setUnitPrice, 0x20, 0x4E, 0, 0, 0, 0, 0, 0]
        ])
    }

    private static func singleInstructionSample(data: [UInt8]) throws -> String {
        try sample(instructionData: [data])
    }

    private static func sample(instructionData: [[UInt8]]) throws -> String {
        var payer = [UInt8](repeating: 0, count: 32)
        payer[0] = 1
        let program = SolanaV0Transaction.computeBudgetProgramKey

        var bytes = try SolanaV0Transaction.encodeCompactLength(1)
        bytes += [UInt8](repeating: 0, count: 64)
        bytes += [0x80, 1, 0, 1]
        bytes += try SolanaV0Transaction.encodeCompactLength(2)
        bytes += payer
        bytes += program
        bytes += [UInt8](repeating: 9, count: 32)
        bytes += try SolanaV0Transaction.encodeCompactLength(instructionData.count)
        for data in instructionData {
            bytes.append(1)
            bytes += try SolanaV0Transaction.encodeCompactLength(0)
            bytes += try SolanaV0Transaction.encodeCompactLength(data.count)
            bytes += data
        }
        bytes += try SolanaV0Transaction.encodeCompactLength(0)
        return Data(bytes).base64EncodedString()
    }
}
