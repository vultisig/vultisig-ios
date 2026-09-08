//
//  TronBandwidthEstimateTests.swift
//  VultisigAppTests
//
//  TRON bills bandwidth for the bytes of the signed transaction, so an
//  estimate built from a per-shape constant is blind to the memo: a send the
//  app budgets as free out of the account's free bandwidth can in fact spill
//  into paid bandwidth, and the fee shown before signing is wrong in the
//  user's disfavour.
//
//  See https://developers.tron.network/docs/resource-model#bandwidth-points.
//

@testable import VultisigApp
import BigInt
import XCTest

final class TronBandwidthEstimateTests: XCTestCase {

    private static let owner = "TKt9bGgWeFFu2yRgULxRhmiBADuoEoadq8"
    private static let recipient = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"

    /// Protobuf overhead of the `data` field carrying the memo: one field tag
    /// plus the single-byte length varint every memo below 128 bytes uses.
    private static let memoFieldOverhead: Int64 = 2

    func testMemolessTransferIsSizedFromTheSerializedTransaction() throws {
        let bytes = try bandwidthBytes(memo: nil)

        // A native transfer serializes to a couple of hundred bytes: two
        // 21-byte addresses, the block reference, two millisecond timestamps,
        // one 65-byte signature and TRON's 64-byte result allowance. The band
        // is wide on purpose — it catches a WalletCore payload that stopped
        // being the raw transaction without pinning an exact wire size.
        XCTAssertGreaterThan(bytes, 150)
        XCTAssertLessThan(bytes, 400)
    }

    func testMemoAddsItsOwnBytesToTheEstimate() throws {
        let memo = String(repeating: "a", count: 50)

        let withoutMemo = try bandwidthBytes(memo: nil)
        let withMemo = try bandwidthBytes(memo: memo)

        XCTAssertEqual(withMemo - withoutMemo, Int64(memo.count) + Self.memoFieldOverhead)
    }

    /// A memo is serialized as UTF-8 bytes, not as characters, so the estimate
    /// has to grow by the byte count — nine here, not three.
    func testMultiByteMemoIsChargedByByteNotByCharacter() throws {
        let memo = "日本語"
        XCTAssertEqual(memo.count, 3)
        XCTAssertEqual(memo.utf8.count, 9)

        let withoutMemo = try bandwidthBytes(memo: nil)
        let withMemo = try bandwidthBytes(memo: memo)

        XCTAssertEqual(withMemo - withoutMemo, Int64(memo.utf8.count) + Self.memoFieldOverhead)
    }

    /// A longer memo crosses the point where the length varint needs a second
    /// byte, and the estimate has to account for that byte too.
    func testLongMemoAccountsForTheWiderLengthVarint() throws {
        let shortMemo = String(repeating: "a", count: 127)
        let longMemo = String(repeating: "a", count: 128)

        let short = try bandwidthBytes(memo: shortMemo)
        let long = try bandwidthBytes(memo: longMemo)

        XCTAssertEqual(long - short, 2)
    }

    func testUnencodableRecipientThrowsSoCallersKeepTheirFallback() {
        XCTAssertThrowsError(try bandwidthBytes(memo: nil, toAddress: ""))
    }

    func testInvalidBlockHeaderHexThrows() {
        XCTAssertThrowsError(
            try TronHelper.nativeTransferBandwidthBytes(
                ownerAddress: Self.owner,
                toAddress: Self.recipient,
                amount: BigInt(1_000_000),
                memo: nil,
                timestamp: 1_757_000_000_000,
                expiration: 1_757_003_600_000,
                blockHeaderTimestamp: 1_757_000_000_000,
                blockHeaderNumber: 74_000_000,
                blockHeaderVersion: 30,
                blockHeaderTxTrieRoot: "not hex",
                blockHeaderParentHash: String(repeating: "02", count: 32),
                blockHeaderWitnessAddress: "41" + String(repeating: "03", count: 20)
            )
        )
    }

    private func bandwidthBytes(
        memo: String?,
        toAddress: String = TronBandwidthEstimateTests.recipient
    ) throws -> Int64 {
        try TronHelper.nativeTransferBandwidthBytes(
            ownerAddress: Self.owner,
            toAddress: toAddress,
            amount: BigInt(1_000_000),
            memo: memo,
            timestamp: 1_757_000_000_000,
            expiration: 1_757_003_600_000,
            blockHeaderTimestamp: 1_757_000_000_000,
            blockHeaderNumber: 74_000_000,
            blockHeaderVersion: 30,
            blockHeaderTxTrieRoot: String(repeating: "01", count: 32),
            blockHeaderParentHash: String(repeating: "02", count: 32),
            blockHeaderWitnessAddress: "41" + String(repeating: "03", count: 20)
        )
    }
}
