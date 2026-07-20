//
//  LimitOrderRecordTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class LimitOrderRecordTests: XCTestCase {

    /// Every field is deliberately distinct from its default so a dropped
    /// field shows up as a concrete mismatch rather than a passing default.
    private func makeFullyPopulatedRecord(inboundTxHash: String = "") -> LimitOrderRecord {
        LimitOrderRecord(
            inboundTxHash: inboundTxHash,
            sourceAsset: "THOR.RUNE",
            sourceAmount: "60012000000",
            sourceDecimals: 8,
            targetAsset: "BTC.BTC",
            destAddress: "bc1qexampledestaddress",
            targetPrice: Decimal(string: "65800.13")!,
            expiryBlocks: 43200,
            createdAt: Date(timeIntervalSince1970: 1_752_000_000),
            // Deliberately NOT `.pending`: that is the initializer default, so a
            // copy that dropped `status` would still pass.
            status: .filled,
            memo: "=<:BTC.BTC:bc1qexampledestaddress:1.5e6",
            expiryHours: 72,
            minOutputOverride: Decimal(string: "0.00512345")!,
            // Populated so `testWithInboundTxHashPreservesEveryOtherField`
            // actually covers them — left at their `nil` default they would
            // match trivially even if `with` dropped them, which is precisely
            // the bug class that test exists to catch.
            sourceAmount1e8: "60012000000",
            tradeTarget: "512345",
            sourceChainRawValue: Chain.thorChain.rawValue
        )
    }

    func testWithInboundTxHashSetsTheHash() {
        let record = makeFullyPopulatedRecord()
        let spliced = record.with(inboundTxHash: "ABC123")

        XCTAssertEqual(spliced.inboundTxHash, "ABC123")
    }

    /// Regression: the done-screen copy silently dropped `minOutputOverride`,
    /// which is the exact figure the order was signed with. Losing it makes the
    /// persisted order fall back to the `targetPrice`-derived output — a
    /// different number from the one the user confirmed.
    func testWithInboundTxHashPreservesMinOutputOverride() {
        let record = makeFullyPopulatedRecord()
        let spliced = record.with(inboundTxHash: "ABC123")

        XCTAssertEqual(spliced.minOutputOverride, Decimal(string: "0.00512345")!)
    }

    func testWithInboundTxHashPreservesANilMinOutputOverride() {
        let record = LimitOrderRecord(
            inboundTxHash: "",
            sourceAsset: "THOR.RUNE",
            sourceAmount: "60012000000",
            sourceDecimals: 8,
            targetAsset: "BTC.BTC",
            destAddress: "bc1qexampledestaddress",
            targetPrice: Decimal(string: "65800.13")!,
            expiryBlocks: 43200,
            minOutputOverride: nil
        )

        XCTAssertNil(record.with(inboundTxHash: "ABC123").minOutputOverride)
    }

    /// Locks the whole copy, not just the field that regressed: `with` differs
    /// from the source record in `inboundTxHash` and nothing else.
    func testWithInboundTxHashPreservesEveryOtherField() {
        let record = makeFullyPopulatedRecord()
        let spliced = record.with(inboundTxHash: "ABC123")

        XCTAssertEqual(spliced, makeFullyPopulatedRecord(inboundTxHash: "ABC123"))
    }
}
