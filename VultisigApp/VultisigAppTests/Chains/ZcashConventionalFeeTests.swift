//
//  ZcashConventionalFeeTests.swift
//  VultisigAppTests
//
//  Golden vectors mirrored from the SDK's zip317.test.ts
//  (packages/core/chain/chains/utxo/fee/zip317.test.ts) — the two
//  implementations must stay byte-identical for MPC co-signing.
//

@testable import VultisigApp
import XCTest

final class ZcashConventionalFeeTests: XCTestCase {
    private let p2pkhOutput: Int64 = 34

    // MARK: - conventionalFee

    func testReturnsTheTenThousandZatFloorForASimpleOneInTwoOutSend() {
        XCTAssertEqual(
            ZcashConventionalFee.conventionalFee(inputCount: 1, outputSizes: [p2pkhOutput, p2pkhOutput]),
            10_000
        )
    }

    func testScalesWithInputCountBeyondTheGraceWindow() {
        XCTAssertEqual(
            ZcashConventionalFee.conventionalFee(inputCount: 4, outputSizes: [p2pkhOutput, p2pkhOutput]),
            20_000
        )
    }

    func testChargesInputActionsFromSerializedBytesNotRawCount() {
        // 75 P2PKH inputs: ceil(75 * 148 / 150) = 74 actions, not 75.
        XCTAssertEqual(
            ZcashConventionalFee.conventionalFee(inputCount: 75, outputSizes: [p2pkhOutput, p2pkhOutput]),
            370_000
        )
    }

    func testCountsLargeOpReturnOutputsAsMultipleActions() {
        // 80-byte memo output: 92 bytes serialized -> with two p2pkh outputs,
        // ceil(160 / 34) = 5 actions -> 25,000 zats.
        XCTAssertEqual(
            ZcashConventionalFee.conventionalFee(inputCount: 1, outputSizes: [p2pkhOutput, p2pkhOutput, 92]),
            25_000
        )
    }

    // MARK: - opReturnOutputSize

    func testSizesAShortMemoWithASingleBytePush() {
        // 9 fixed bytes + 2 push overhead + data length.
        XCTAssertEqual(ZcashConventionalFee.opReturnOutputSize(memoSize: 40), 51)
    }

    func testAddsAByteOfPushOverheadOnceTheMemoExceeds75Bytes() {
        XCTAssertEqual(ZcashConventionalFee.opReturnOutputSize(memoSize: 75), 86)
        XCTAssertEqual(ZcashConventionalFee.opReturnOutputSize(memoSize: 76), 88)
    }

    func testHandlesCompactSizeAndPushdataBoundariesForLongMemos() {
        // 250-byte memo: script length 253 crosses the CompactSize 1->3 byte threshold.
        XCTAssertEqual(ZcashConventionalFee.opReturnOutputSize(memoSize: 249), 261)
        XCTAssertEqual(ZcashConventionalFee.opReturnOutputSize(memoSize: 250), 264)
        // 256-byte memo: push opcode crosses PUSHDATA1 -> PUSHDATA2.
        XCTAssertEqual(ZcashConventionalFee.opReturnOutputSize(memoSize: 255), 269)
        XCTAssertEqual(ZcashConventionalFee.opReturnOutputSize(memoSize: 256), 271)
    }

    func testHandlesUpperCompactSizeAndPushdataBoundaries() {
        // Beyond the SDK's vectors: pin the upper thresholds so the Swift
        // switch statements provably match the TS ternary chain.
        // Script length 65535 -> 65536 crosses the CompactSize 3 -> 5 byte
        // threshold (memo 65531 -> script 65535; memo 65532 -> script 65536).
        XCTAssertEqual(ZcashConventionalFee.opReturnOutputSize(memoSize: 65_531), 65_546)
        XCTAssertEqual(ZcashConventionalFee.opReturnOutputSize(memoSize: 65_532), 65_549)
        // Memo 65535 -> 65536 crosses the PUSHDATA2 -> PUSHDATA4 threshold
        // (push overhead 4 -> 6 bytes).
        XCTAssertEqual(ZcashConventionalFee.opReturnOutputSize(memoSize: 65_535), 65_552)
        XCTAssertEqual(ZcashConventionalFee.opReturnOutputSize(memoSize: 65_536), 65_555)
    }

    // MARK: - transparentOutputSizes

    func testReturnsRecipientOnlyWhenThereIsNoChangeAndNoMemo() {
        XCTAssertEqual(ZcashConventionalFee.transparentOutputSizes(change: 0, memoSize: 0), [34])
    }

    func testAddsAChangeOutputOnlyWhenChangeIsPositive() {
        XCTAssertEqual(ZcashConventionalFee.transparentOutputSizes(change: 1, memoSize: 0), [34, 34])
    }

    func testAppendsTheOpReturnSizeForAMemoSend() {
        XCTAssertEqual(ZcashConventionalFee.transparentOutputSizes(change: 1, memoSize: 40), [34, 34, 51])
    }

    // MARK: - ceilDiv

    func testCeilDivRoundsUpToTheSmallestClearingMultiple() {
        XCTAssertEqual(ZcashConventionalFee.ceilDiv(0, 34), 0)
        XCTAssertEqual(ZcashConventionalFee.ceilDiv(34, 34), 1)
        XCTAssertEqual(ZcashConventionalFee.ceilDiv(35, 34), 2)
        XCTAssertEqual(ZcashConventionalFee.ceilDiv(20_000, 260), 77)
    }
}
