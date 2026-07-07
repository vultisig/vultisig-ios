//
//  CardanoCIP20Tests.swift
//  VultisigApp
//

@testable import VultisigApp
import WalletCore
import XCTest

/// Byte-parity fixtures shared with the SDK's
/// `packages/core/mpc/tx/compile/cardano/buildCip20AuxData.test.ts`. The CIP-20
/// CBOR bytes and blake2b-256 aux hash MUST be identical across iOS / Android /
/// Extension or MPC co-signers disagree on the Cardano sighash. Any drift here
/// or in the SDK encoder breaks one of these tests.
final class CardanoCIP20Tests: XCTestCase {

    // MARK: - memoToChunks

    func testReturnsSingleChunkForShortMemo() {
        XCTAssertEqual(CardanoCIP20.memoToChunks("hello world"), ["hello world"])
    }

    func testReturnsSingleEmptyChunkForEmptyInput() {
        XCTAssertEqual(CardanoCIP20.memoToChunks(""), [""])
    }

    func testSplitsExactlyOn64ByteBoundaryForAscii() {
        let memo65 = String(repeating: "a", count: 65)
        let chunks = CardanoCIP20.memoToChunks(memo65)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].utf8.count, 64)
        XCTAssertEqual(chunks[1].utf8.count, 1)
    }

    func testDoesNotSplitA64ByteMemo() {
        let memo64 = String(repeating: "x", count: 64)
        XCTAssertEqual(CardanoCIP20.memoToChunks(memo64), [memo64])
    }

    func testDoesNotTear4ByteCodepointStraddlingBoundary() {
        // 63 ASCII 'a' + U+1F600 (4 bytes) + 'b'. A naive byte-cut would tear
        // the emoji at byte 63 and produce U+FFFD on decode.
        let memo = String(repeating: "a", count: 63) + "\u{1F600}" + "b"
        let chunks = CardanoCIP20.memoToChunks(memo)
        XCTAssertEqual(chunks.joined(), memo)
        XCTAssertFalse(chunks.joined().contains("\u{FFFD}"))
        XCTAssertLessThanOrEqual(chunks[0].utf8.count, 64)
        XCTAssertTrue(chunks[1].contains("\u{1F600}"))
    }

    func testDoesNotTear2ByteCodepointStraddlingBoundary() {
        // 63 ASCII 'a' + 'ñ' (U+00F1, 2 bytes) + 'c'
        let memo = String(repeating: "a", count: 63) + "ñ" + "c"
        let chunks = CardanoCIP20.memoToChunks(memo)
        XCTAssertEqual(chunks.joined(), memo)
        XCTAssertFalse(chunks.joined().contains("\u{FFFD}"))
    }

    func testDoesNotTear3ByteCodepointStraddlingBoundary() {
        // 62 ASCII 'a' + '日' (U+65E5, 3 bytes spanning bytes 62-64) + 'd'
        let memo = String(repeating: "a", count: 62) + "日" + "d"
        let chunks = CardanoCIP20.memoToChunks(memo)
        XCTAssertEqual(chunks.joined(), memo)
        XCTAssertFalse(chunks.joined().contains("\u{FFFD}"))
    }

    func testMultiByteMemoRoundTripsThroughChunks() {
        let memo = String(repeating: "a", count: 63) + "\u{1F600}" + "b"
        let chunks = CardanoCIP20.memoToChunks(memo)
        XCTAssertEqual(chunks.joined(), memo)
        XCTAssertFalse(chunks.joined().contains("\u{FFFD}"))
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.utf8.count, 64)
        }
    }

    // MARK: - buildAuxData byte parity

    /// Pinned canonical CBOR for `{ 674: { "msg": ["hello world"] } }`:
    ///   A1              map(1)
    ///     19 02 A2      uint(674)
    ///     A1            map(1)
    ///       63 6D 73 67 text("msg")
    ///       81          array(1)
    ///         6B ...    text(11) "hello world"
    func testBuildAuxDataProducesPinnedCborForHelloWorld() {
        // a1 1902a2 a1 636d7367 81 6b <"hello world">
        let expectedHex = "a11902a2a1636d7367816b" + Data("hello world".utf8).hexString
        let (auxDataCbor, _) = CardanoCIP20.buildAuxData(memo: "hello world")
        XCTAssertEqual(auxDataCbor.hexString, expectedHex)
    }

    func testBuildAuxDataEncodesLabel674AndMsgKey() {
        let (auxDataCbor, _) = CardanoCIP20.buildAuxData(memo: "hello world")
        let hex = auxDataCbor.hexString
        // Outer map(1) + uint(674) = a1 1902a2 ; inner map(1) + text "msg" = a1 636d7367
        XCTAssertTrue(hex.hasPrefix("a11902a2a1636d7367"))
    }

    func testBuildAuxDataChunksA64ByteChunkHeadCorrectly() {
        // A 65-byte ASCII memo → two text chunks: one 64-byte (head 78 40) and
        // one 1-byte (head 61). Verifies the 24 ≤ len < 256 head form.
        let memo = String(repeating: "a", count: 65)
        let (auxDataCbor, _) = CardanoCIP20.buildAuxData(memo: memo)
        let hex = auxDataCbor.hexString
        // array(2) header before the chunks
        XCTAssertTrue(hex.contains("82"))
        // 64-byte text head 0x78 0x40 followed by 64 'a' (0x61)
        XCTAssertTrue(hex.contains("7840" + String(repeating: "61", count: 64)))
    }

    func testBuildAuxDataEmptyMemoEncodesSingleEmptyChunk() {
        // { 674: { "msg": [""] } } → ... 81 60  (array(1), text(0))
        let (auxDataCbor, _) = CardanoCIP20.buildAuxData(memo: "")
        XCTAssertEqual(auxDataCbor.hexString, "a11902a2a1636d7367" + "8160")
    }

    func testAuxDataHashIsBlake2b256OfCbor() {
        let (auxDataCbor, auxDataHash) = CardanoCIP20.buildAuxData(memo: "vultisig-test")
        XCTAssertEqual(auxDataHash.count, 32)
        XCTAssertEqual(auxDataHash, Hash.blake2b(data: auxDataCbor, size: 32))
        XCTAssertTrue(auxDataHash.contains { $0 != 0 })
    }
}
