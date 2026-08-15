//
//  TransientObservationTests.swift
//  VultisigAppTests
//
//  Per-session state that a view branches on has to PUBLISH when it changes,
//  not merely end up holding the right value.
//
//  Asserting on the resulting value cannot show that. `vault.fastVaultEligibility`
//  read back the value the refresher had just written even while it was a plain
//  SwiftData `@Transient` property — and a `@Transient` write notifies nobody, so
//  the view branching on `isFastVault` was never re-evaluated. It appeared to
//  work only because an unrelated `Storage.shared.save()` re-rendered the tree
//  soon after. A value-only test passes against both implementations and would
//  have caught nothing.
//
//  These tests therefore observe with `withObservationTracking` and assert on
//  whether a change was published, which is the property the views actually
//  depend on. Each probe reads the same expression the view reads — `isFastVault`
//  — rather than the underlying storage, so it fails if the derived property
//  stops being reachable from the observation graph for any reason, not just the
//  one known cause.
//

@testable import VultisigApp
import Observation
import XCTest

/// Reference box so the `@Sendable` `onChange` closure can report back without
/// capturing a mutable local. Every access is main-actor and synchronous —
/// `onChange` fires from inside the write being probed, on the same thread.
private final class ChangeRecorder: @unchecked Sendable {
    private(set) var didChange = false
    func record() { didChange = true }
}

/// Runs `read` under observation tracking, performs `write`, and reports whether
/// the registrar published a change to anything `read` touched.
@MainActor
private func publishesChange(reading read: () -> Void, writing write: () -> Void) -> Bool {
    let recorder = ChangeRecorder()
    withObservationTracking {
        read()
    } onChange: {
        recorder.record()
    }
    write()
    return recorder.didChange
}

@MainActor
final class TransientObservationTests: XCTestCase {

    // MARK: - Vault.isFastVault

    /// The acceptance case: a view branching on `isFastVault` is invalidated when
    /// the refresher resolves eligibility, and nothing else is needed to make that
    /// happen. `saveStorage` is a no-op here, so a save cannot be what re-renders
    /// the tree — the write itself has to publish. Fails against a
    /// `@Transient`-backed cache, which publishes nothing at all.
    func testRefresherResolvingEligibilityPublishesIsFastVault() async {
        let vault = SendFormFixture.makeVault()
        let refresher = FastVaultEligibilityRefresher(
            checkEligibility: { _ in true },
            saveStorage: { },
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )

        let recorder = ChangeRecorder()
        withObservationTracking {
            _ = vault.isFastVault
        } onChange: {
            recorder.record()
        }

        await refresher.refresh(vault)

        XCTAssertTrue(recorder.didChange, "resolving eligibility must publish to readers of isFastVault")
        XCTAssertTrue(vault.isFastVault)
    }

    /// `isFastVault` short-circuits on `fastVaultEligibilityCheckedAt == nil`, so
    /// on a cold vault the stamp is the only one of the two inputs the reader
    /// reaches. It has to publish on its own.
    func testStampAlonePublishesIsFastVault() {
        let vault = SendFormFixture.makeVault()

        let published = publishesChange {
            _ = vault.isFastVault
        } writing: {
            vault.fastVaultEligibilityCheckedAt = Date(timeIntervalSince1970: 1)
        }

        XCTAssertTrue(published)
    }

    /// Once the cache is warm the flag is reached too, and flipping it — the
    /// eligibility genuinely changing between refreshes — must publish.
    func testEligibilityFlagAlonePublishesIsFastVault() {
        let vault = SendFormFixture.makeVault()
        vault.fastVaultEligibilityCheckedAt = Date(timeIntervalSince1970: 1)

        let published = publishesChange {
            _ = vault.isFastVault
        } writing: {
            vault.fastVaultEligibility = true
        }

        XCTAssertTrue(published)
    }

    /// The other half of the guard: a refresh that resolves to the value already
    /// cached must not invalidate anyone. An unguarded box would notify on every
    /// write, which is the shape that drives a runaway re-render when the writer
    /// is deferred.
    func testRedundantEligibilityWriteDoesNotPublish() {
        let vault = SendFormFixture.makeVault()
        vault.fastVaultEligibility = true
        vault.fastVaultEligibilityCheckedAt = Date(timeIntervalSince1970: 1)

        let published = publishesChange {
            _ = vault.isFastVault
        } writing: {
            vault.fastVaultEligibility = true
            vault.fastVaultEligibilityCheckedAt = Date(timeIntervalSince1970: 1)
        }

        XCTAssertFalse(published)
    }

    /// Vaults must not share eligibility storage. A cache keyed by anything other
    /// than the instance — `pubKeyECDSA`, say, which this fixture leaves identical
    /// across vaults — would cross-talk, invalidating every reader of the other
    /// vault and reporting the wrong answer.
    func testEligibilityIsPerVault() {
        let vaultA = SendFormFixture.makeVault()
        let vaultB = SendFormFixture.makeVault()

        let published = publishesChange {
            _ = vaultB.isFastVault
        } writing: {
            vaultA.fastVaultEligibility = true
            vaultA.fastVaultEligibilityCheckedAt = Date(timeIntervalSince1970: 1)
        }

        XCTAssertFalse(published, "vaultB must not be invalidated by a write to vaultA")
        XCTAssertTrue(vaultA.isFastVault)
        XCTAssertFalse(vaultB.isFastVault)
        XCTAssertNil(vaultB.fastVaultEligibilityCheckedAt)
    }

    /// A server-side share is never fast-signable regardless of what the cache
    /// says, and that short-circuit has to survive the storage change.
    func testServerPartyIsNeverFastVault() {
        let vault = SendFormFixture.makeVault(localPartyID: "Server-1")
        vault.fastVaultEligibility = true
        vault.fastVaultEligibilityCheckedAt = Date(timeIntervalSince1970: 1)

        XCTAssertFalse(vault.isFastVault)
    }

    // MARK: - Coin.hasPendingBalance

    /// `CoinDetailHeaderView` branches on `hasPendingBalance` to decide whether
    /// the pending line exists at all, so an inbound payment landing in the
    /// mempool has to invalidate that read on its own — `BalanceService` writing
    /// `pendingRawBalance` is the only event involved.
    func testInboundBalanceArrivingPublishesHasPendingBalance() {
        let coin = SendFormFixture.makeBTC()

        let published = publishesChange {
            _ = coin.hasPendingBalance
        } writing: {
            coin.pendingRawBalance = "250000"
        }

        XCTAssertTrue(published)
        XCTAssertTrue(coin.hasPendingBalance)
        XCTAssertEqual(coin.pendingBalanceDecimal, Decimal(string: "0.0025"))
    }

    /// The line has to disappear again once the transaction confirms and the
    /// pending amount folds into the balance.
    func testPendingBalanceClearingPublishesHasPendingBalance() {
        let coin = SendFormFixture.makeBTC()
        coin.pendingRawBalance = "250000"

        let published = publishesChange {
            _ = coin.hasPendingBalance
        } writing: {
            coin.pendingRawBalance = "0"
        }

        XCTAssertTrue(published)
        XCTAssertFalse(coin.hasPendingBalance)
    }

    /// A second inbound payment while one is already pending does not flip the
    /// boolean, but it does change the amount the view prints. Observing only
    /// `hasPendingBalance` would miss it, so the formatted string the view
    /// actually renders gets its own probe.
    func testPendingAmountChangePublishesFormattedString() {
        let coin = SendFormFixture.makeBTC()
        coin.pendingRawBalance = "250000"

        let published = publishesChange {
            _ = coin.pendingBalanceStringWithTicker
        } writing: {
            coin.pendingRawBalance = "300000"
        }

        XCTAssertTrue(published)
        XCTAssertTrue(coin.hasPendingBalance)
    }

    /// A balance refresh that reports the same mempool state must not invalidate
    /// the view. Balances refresh on a timer, so an unguarded box would re-render
    /// every coin detail screen on every poll for no reason.
    func testRedundantPendingBalanceWriteDoesNotPublish() {
        let coin = SendFormFixture.makeBTC()
        coin.pendingRawBalance = "250000"

        let published = publishesChange {
            _ = coin.hasPendingBalance
            _ = coin.pendingBalanceStringWithTicker
        } writing: {
            coin.pendingRawBalance = "250000"
        }

        XCTAssertFalse(published)
    }

    /// Coins must not share pending-balance storage. These two fixtures have the
    /// same `id`, which is what a keyed cache would collide on — one coin's
    /// mempool would then show up on another's screen.
    func testPendingBalanceIsPerCoin() {
        let coinA = SendFormFixture.makeBTC()
        let coinB = SendFormFixture.makeBTC()

        let published = publishesChange {
            _ = coinB.hasPendingBalance
        } writing: {
            coinA.pendingRawBalance = "250000"
        }

        XCTAssertFalse(published, "coinB must not be invalidated by a write to coinA")
        XCTAssertTrue(coinA.hasPendingBalance)
        XCTAssertFalse(coinB.hasPendingBalance)
        XCTAssertEqual(coinB.pendingRawBalance, "0")
    }
}
