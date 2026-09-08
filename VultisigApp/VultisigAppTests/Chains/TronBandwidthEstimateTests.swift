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

    /// Real recorded sender, from the captured SwapKit TRON quote in
    /// `Swap/SwapKit/__fixtures__/v3-tron-final-swap-fresh.json`. Every TRON
    /// address decodes to the same 21-byte payload, so the byte counts below do
    /// not depend on which valid address is used — but an address that fails
    /// base58check makes WalletCore refuse to build the transaction at all.
    private static let owner = "TLBaRhANQoJFTqre9Nf1mjuwNWjCJeYqUL"
    private static let recipient = "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t"

    /// Protobuf overhead of the `data` field carrying the memo: one field tag
    /// plus the single-byte length varint every memo below 128 bytes uses.
    private static let memoFieldOverhead: Int64 = 2

    /// Hand-derived from TRON's wire format for the fixture below, so the
    /// signature framing and the result allowance are pinned rather than
    /// merely bracketed. Field numbers from `Transaction.raw` (ref_block_bytes
    /// 1, ref_block_hash 4, expiration 8, data 10, contract 11, timestamp 14);
    /// `ref_block_num` and `fee_limit` are left at their proto3 defaults and so
    /// are not serialized.
    ///
    /// Cross-checked against the recorded `raw_data_hex` in
    /// `Swap/SwapKit/__fixtures__/v3-tron-final-swap-fresh.json`, a real TRON
    /// transaction: it opens `0a 02 8975` (ref_block_bytes, 4 bytes),
    /// `22 08 …` (ref_block_hash, 10), `40 …` (expiration, 7), carries its
    /// addresses as `0a 15 41…` / `12 15 41…` (21-byte payloads), and ends
    /// `70 …` (timestamp, 7) with no `ref_block_num` anywhere.
    ///
    ///     TransferContract  owner 1+1+21, to 1+1+21, amount 1+3      =  50
    ///     Any               type_url 1+1+45, value 1+1+50            =  99
    ///     Contract          type 1+1, parameter 1+1+99               = 103
    ///     raw_data          ref_block_bytes 1+1+2,  ref_block_hash 1+1+8,
    ///                       expiration 1+6, contract 1+1+103,
    ///                       timestamp 1+6                            = 133
    ///     signed tx         raw_data 1+2+133, signature 1+1+65       = 203
    ///     + MAX_RESULT_SIZE_IN_TX                                    =  64
    ///                                                                = 267
    private static let memolessTransferBytes: Int64 = 267

    func testMemolessTransferMatchesTheHandDerivedByteCount() throws {
        XCTAssertEqual(try bandwidthBytes(memo: nil), Self.memolessTransferBytes)
    }

    /// The same derivation with a 50-byte memo, whose `data` field adds
    /// 1 tag + 1 length + 50 = 52 bytes.
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
