//
//  MayaCacaoUnstakeMetadataTests.swift
//  VultisigAppTests
//
//  Maturity gating for the MayaChain CACAO single-pool unstake CTA.
//

@testable import VultisigApp
import XCTest

final class MayaCacaoUnstakeMetadataTests: XCTestCase {

    private let blockTime: TimeInterval = 6
    /// 21-day maturity window (live mimir value at time of writing): 302400 blocks.
    private let maturityBlocks: Int64 = 302_400

    // MARK: - Matured position enables unstake

    func test_maturedPosition_enablesUnstake() {
        // last_deposit_height + maturity is already behind the snapshot height ⇒ remaining 0.
        let meta = UnstakeMetadata(
            lastDepositHeight: 1_000,
            maturityBlocks: maturityBlocks,
            snapshotHeight: 1_000 + maturityBlocks + 10,
            snapshotTimestamp: Date().timeIntervalSince1970
        )

        XCTAssertTrue(meta.canUnstake())
        XCTAssertEqual(meta.remainingBlocks(), 0)
        XCTAssertEqual(meta.remainingSeconds(), 0)
        XCTAssertNil(meta.unstakeMessage(for: TokensStore.cacao), "Mature ⇒ no maturity hint.")
    }

    // MARK: - Not-yet-matured position is gated with correct remaining

    func test_notYetMatured_isGatedWithCorrectRemaining() {
        let reference = Date(timeIntervalSince1970: 1_000_000)
        let remainingBlocks: Int64 = 14_400 // exactly one day of 6s blocks

        let meta = UnstakeMetadata(
            lastDepositHeight: 1_000,
            maturityBlocks: maturityBlocks,
            // snapshot height leaves exactly `remainingBlocks` to go.
            snapshotHeight: 1_000 + maturityBlocks - remainingBlocks,
            snapshotTimestamp: reference.timeIntervalSince1970
        )

        XCTAssertFalse(meta.canUnstake(at: reference))
        XCTAssertEqual(meta.remainingBlocks(at: reference), remainingBlocks)
        XCTAssertEqual(meta.remainingSeconds(at: reference), Double(remainingBlocks) * blockTime)
        XCTAssertNotNil(meta.unstakeMessage(for: TokensStore.cacao, at: reference))
    }

    // MARK: - Recompute is live (not frozen)

    /// The same raw inputs evaluated at a later wall-clock time must advance toward maturity and
    /// eventually flip to enabled — proving the gate re-derives instead of comparing a frozen date.
    func test_recomputeIsLive_flipsToEnabledAsTimePasses() {
        let snapshot = Date(timeIntervalSince1970: 1_000_000)
        let remainingBlocks: Int64 = 14_400 // one day to go at snapshot time

        let meta = UnstakeMetadata(
            lastDepositHeight: 1_000,
            maturityBlocks: maturityBlocks,
            snapshotHeight: 1_000 + maturityBlocks - remainingBlocks,
            snapshotTimestamp: snapshot.timeIntervalSince1970
        )

        // At snapshot time: still locked.
        XCTAssertFalse(meta.canUnstake(at: snapshot))

        // Halfway through the remaining window: still locked, but less remaining.
        let halfway = snapshot.addingTimeInterval(Double(remainingBlocks) * blockTime / 2)
        XCTAssertFalse(meta.canUnstake(at: halfway))
        XCTAssertLessThan(meta.remainingBlocks(at: halfway), remainingBlocks)

        // Past the full window: now mature without any refresh.
        let afterMaturity = snapshot.addingTimeInterval(Double(remainingBlocks) * blockTime + 60)
        XCTAssertTrue(meta.canUnstake(at: afterMaturity))
        XCTAssertEqual(meta.remainingBlocks(at: afterMaturity), 0)
    }

    func test_remainingNeverGoesNegative() {
        let meta = UnstakeMetadata(
            lastDepositHeight: 1_000,
            maturityBlocks: maturityBlocks,
            snapshotHeight: 1_000 + maturityBlocks + 50_000,
            snapshotTimestamp: Date().timeIntervalSince1970
        )
        XCTAssertEqual(meta.remainingBlocks(), 0)
        XCTAssertGreaterThanOrEqual(meta.remainingSeconds(), 0)
    }

    // MARK: - Unknown / unverified state

    func test_unknownState_gatesAndExplains() {
        let meta = UnstakeMetadata.unknown

        XCTAssertTrue(meta.isUnknown)
        XCTAssertFalse(meta.canUnstake(), "Couldn't-verify ⇒ CTA must stay gated.")
        XCTAssertEqual(
            meta.unstakeMessage(for: TokensStore.cacao),
            "cacaoUnstakeMaturityUnknownMessage".localized,
            "Unknown ⇒ explicit explanation, not a silent grey button."
        )
    }

    // MARK: - Non-cacao coins get no hint

    func test_unstakeMessage_nilForNonCacaoCoin() {
        let meta = UnstakeMetadata(
            lastDepositHeight: 1_000,
            maturityBlocks: maturityBlocks,
            snapshotHeight: 1_000,
            snapshotTimestamp: Date().timeIntervalSince1970
        )
        XCTAssertNil(meta.unstakeMessage(for: .example))
    }

    // MARK: - Migration-safe decoding of the legacy persisted shape

    /// Older builds persisted an absolute `unstakeAvailableDate`. Decoding must not crash and must
    /// keep gating sanely: a future legacy unlock ⇒ still locked; a past unlock ⇒ mature.
    func test_legacyDecoding_futureUnlock_staysLocked() throws {
        let future = Date().addingTimeInterval(24 * 60 * 60).timeIntervalSince1970
        let json = "{\"unstakeAvailableDate\": \(future)}".data(using: .utf8)!

        let meta = try JSONDecoder().decode(UnstakeMetadata.self, from: json)

        XCTAssertFalse(meta.isUnknown)
        XCTAssertFalse(meta.canUnstake(), "Legacy future unlock ⇒ still gated.")
        XCTAssertGreaterThan(meta.remainingBlocks(), 0)
    }

    func test_legacyDecoding_pastUnlock_isMature() throws {
        let past = Date().addingTimeInterval(-60).timeIntervalSince1970
        let json = "{\"unstakeAvailableDate\": \(past)}".data(using: .utf8)!

        let meta = try JSONDecoder().decode(UnstakeMetadata.self, from: json)

        XCTAssertFalse(meta.isUnknown)
        XCTAssertTrue(meta.canUnstake(), "Legacy past unlock ⇒ mature.")
        XCTAssertEqual(meta.remainingBlocks(), 0)
    }

    /// A round-trip through the new encoder preserves the raw inputs.
    func test_codableRoundTrip_preservesRawInputs() throws {
        let original = UnstakeMetadata(
            lastDepositHeight: 12_345,
            maturityBlocks: maturityBlocks,
            snapshotHeight: 50_000,
            snapshotTimestamp: 1_700_000_000
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UnstakeMetadata.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}
