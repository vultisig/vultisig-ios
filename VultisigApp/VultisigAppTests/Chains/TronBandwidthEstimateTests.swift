//
//  TronBandwidthEstimateTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

final class TronBandwidthEstimateTests: XCTestCase {

    /// Must pass base58check: WalletCore refuses to build the transaction
    /// otherwise. Recorded sender from `__fixtures__/v3-tron-final-swap-fresh.json`.
    private static let owner = "TLBaRhANQoJFTqre9Nf1mjuwNWjCJeYqUL"
    private static let recipient = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"

    /// Memo `data` field overhead: tag + one-byte length varint.
    private static let memoFieldOverhead: Int64 = 2

    /// Hand-derived from TRON's wire format; derivation in the PR description.
    private static let memolessTransferBytes: Int64 = 267

    func testMemolessTransferMatchesTheHandDerivedByteCount() throws {
        XCTAssertEqual(try bandwidthBytes(memo: nil), Self.memolessTransferBytes)
    }

    func testMemoBearingTransferMatchesTheHandDerivedByteCount() throws {
        let memo = String(repeating: "a", count: 50)

        XCTAssertEqual(try bandwidthBytes(memo: memo), Self.memolessTransferBytes + 52)
    }

    func testMemoAddsItsOwnBytesToTheEstimate() throws {
        let memo = String(repeating: "a", count: 50)

        let withoutMemo = try bandwidthBytes(memo: nil)
        let withMemo = try bandwidthBytes(memo: memo)

        XCTAssertEqual(withMemo - withoutMemo, Int64(memo.count) + Self.memoFieldOverhead)
    }

    func testMultiByteMemoIsChargedByByteNotByCharacter() throws {
        let memo = "日本語"
        XCTAssertEqual(memo.count, 3)
        XCTAssertEqual(memo.utf8.count, 9)

        let withoutMemo = try bandwidthBytes(memo: nil)
        let withMemo = try bandwidthBytes(memo: memo)

        XCTAssertEqual(withMemo - withoutMemo, Int64(memo.utf8.count) + Self.memoFieldOverhead)
    }

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
