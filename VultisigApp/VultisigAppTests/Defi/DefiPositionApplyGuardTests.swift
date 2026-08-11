//
//  DefiPositionApplyGuardTests.swift
//  VultisigAppTests
//
//  `LPPosition.apply(_:)` and `StakePosition.apply(_:)` must leave every stored
//  property alone when the incoming DTO already matches what is stored.
//
//  Asserting on the resulting VALUES cannot show that — a blind re-assignment of
//  an identical value leaves the values identical too, so a test written that way
//  passes against both the guarded and the unguarded implementation. What
//  separates them is the notification: SwiftData's `@Model` setter routes through
//  the Observation registrar and notifies WITHOUT comparing new to old, so an
//  unguarded `apply` invalidates every SwiftUI view reading the position on every
//  call, however little the refresh actually changed. These tests therefore
//  observe the position with `withObservationTracking` and assert on whether a
//  change was published, which is the property that actually matters.
//
//  The per-field sweeps are the other half. The failure they prevent is a field
//  that is written but not compared: the guard returns early, the write never
//  runs, and a real update is silently dropped. Every field either method assigns
//  gets its own case.
//

@testable import VultisigApp
import Observation
import SwiftData
import XCTest

/// Reference box so the `@Sendable` `onChange` closure can report back without
/// capturing a mutable local. Every access is main-actor and synchronous —
/// `onChange` fires from inside the `apply(_:)` call, on the same thread.
private final class ChangeRecorder: @unchecked Sendable {
    private(set) var didChange = false
    func record() { didChange = true }
}

private enum Fixture {
    static let lpCoin1 = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
    static let lpCoin2 = CoinMeta.make(chain: .bitcoin, ticker: "BTC")
    static let stakeCoin = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
    static let stakeRewardCoin = CoinMeta.make(chain: .thorChain, ticker: "TCY")
    static let unstakeMetadata = UnstakeMetadata(
        lastDepositHeight: 100,
        maturityBlocks: 10,
        snapshotHeight: 105,
        snapshotTimestamp: 1_700_000_000
    )
    static let otherUnstakeMetadata = UnstakeMetadata(
        lastDepositHeight: 200,
        maturityBlocks: 20,
        snapshotHeight: 205,
        snapshotTimestamp: 1_700_000_500
    )
    static let bondCoin = CoinMeta.make(chain: .thorChain, ticker: "RUNE")
    static let bondNode = BondNode(coin: bondCoin, address: "thor1node", state: .active)
    static let churnDate = Date(timeIntervalSince1970: 1_700_000_000)
    static let otherChurnDate = Date(timeIntervalSince1970: 1_700_090_000)
}

// MARK: - DTO factories

/// Baseline LP DTO. Every parameter defaults to the baseline value, so a case
/// overriding exactly one produces a DTO differing in exactly that field.
private func lpDto(
    coin1: CoinMeta = Fixture.lpCoin1,
    coin1Amount: Decimal = 10,
    coin2: CoinMeta = Fixture.lpCoin2,
    coin2Amount: Decimal = 20,
    poolName: String = "BTC.BTC",
    poolUnits: String = "1000",
    apr: Double = 0.05
) -> LPPositionData {
    LPPositionData(
        coin1: coin1,
        coin1Amount: coin1Amount,
        coin2: coin2,
        coin2Amount: coin2Amount,
        poolName: poolName,
        poolUnits: poolUnits,
        apr: apr
    )
}

/// Baseline stake DTO. Optionals default to NON-nil baseline values so a case can
/// express "this field went away" by passing `nil` explicitly, which is a real
/// transition (rewards cleared, a pending withdrawal completing) and one an
/// over-eager guard could swallow.
private func stakeDto(
    coin: CoinMeta = Fixture.stakeCoin,
    type: StakePositionType = .stake,
    amount: Decimal = 10,
    availableToUnstake: Decimal? = 4,
    apr: Double? = 0.1,
    estimatedReward: Decimal? = 1,
    nextPayout: TimeInterval? = 100,
    rewards: Decimal? = 2,
    rewardCoin: CoinMeta? = Fixture.stakeRewardCoin,
    unstakeMetadata: UnstakeMetadata? = Fixture.unstakeMetadata,
    poolAddress: String? = "pool-address",
    poolImplementation: String? = "whales",
    poolName: String? = "Pool A",
    withdrawalUnlockTime: TimeInterval? = 500,
    stakeAccountPubkey: String? = nil,
    validatorVotePubkey: String? = "vote-1",
    activationState: String? = "active"
) -> StakePositionData {
    StakePositionData(
        coin: coin,
        type: type,
        amount: amount,
        availableToUnstake: availableToUnstake,
        apr: apr,
        estimatedReward: estimatedReward,
        nextPayout: nextPayout,
        rewards: rewards,
        rewardCoin: rewardCoin,
        unstakeMetadata: unstakeMetadata,
        poolAddress: poolAddress,
        poolImplementation: poolImplementation,
        poolName: poolName,
        withdrawalUnlockTime: withdrawalUnlockTime,
        stakeAccountPubkey: stakeAccountPubkey,
        validatorVotePubkey: validatorVotePubkey,
        activationState: activationState
    )
}

// MARK: - Observation probes

/// Applies `dto` while observing every property `LPPosition.apply(_:)` can write,
/// and reports whether the Observation registrar published a change.
///
/// Every writable property has to be read inside the tracking closure: an
/// unobserved property could be written without the probe noticing, and the test
/// would pass vacuously.
@MainActor
private func applyPublishesChange(_ position: LPPosition, _ dto: LPPositionData) -> Bool {
    let recorder = ChangeRecorder()
    withObservationTracking {
        _ = position.coin1
        _ = position.coin1Amount
        _ = position.coin2Amount
        _ = position.poolName
        _ = position.poolUnits
        _ = position.apr
        _ = position.lastUpdated
    } onChange: {
        recorder.record()
    }
    position.apply(dto)
    return recorder.didChange
}

/// Stake counterpart of ``applyPublishesChange(_:_:)``, reading all sixteen
/// properties `StakePosition.apply(_:)` can write.
@MainActor
private func applyPublishesChange(_ position: StakePosition, _ dto: StakePositionData) -> Bool {
    let recorder = ChangeRecorder()
    withObservationTracking {
        _ = position.stakeAccountPubkey
        _ = position.type
        _ = position.amount
        _ = position.availableToUnstake
        _ = position.apr
        _ = position.estimatedReward
        _ = position.nextPayout
        _ = position.rewards
        _ = position.rewardCoin
        _ = position.unstakeMetadata
        _ = position.poolAddress
        _ = position.poolImplementation
        _ = position.poolName
        _ = position.withdrawalUnlockTime
        _ = position.validatorVotePubkey
        _ = position.activationState
    } onChange: {
        recorder.record()
    }
    position.apply(dto)
    return recorder.didChange
}

/// Bond rows are upserted by copying fields inline in
/// `DefiPositionsStorageService.upsert(_:for:)` rather than through an
/// `apply(_:)` on the model, so this probe drives the real service call — which
/// also puts the `Storage.shared.save()` + `.defiPositionsDidChange` post on the
/// measured path, exactly as production runs it.
@MainActor
private func upsertPublishesChange(
    _ positions: [BondPosition],
    for vault: Vault,
    observing existing: BondPosition
) throws -> Bool {
    let recorder = ChangeRecorder()
    withObservationTracking {
        _ = existing.amount
        _ = existing.apy
        _ = existing.nextReward
        _ = existing.nextChurn
    } onChange: {
        recorder.record()
    }
    try DefiPositionsStorageService().upsert(positions, for: vault)
    return recorder.didChange
}

/// Mirrors how `THORChainBondInteractor.materialize` builds rows: a fresh
/// `BondPosition` bound to the same vault, whose `id` therefore collides with the
/// persisted row and drives the upsert's update branch.
@MainActor
private func bondPosition(
    node: BondNode = Fixture.bondNode,
    amount: Decimal = 100,
    apy: Double = 0.15,
    nextReward: Decimal = 5,
    nextChurn: Date? = Fixture.churnDate,
    vault: Vault
) -> BondPosition {
    BondPosition(
        node: node,
        amount: amount,
        apy: apy,
        nextReward: nextReward,
        nextChurn: nextChurn,
        vault: vault
    )
}

@MainActor
final class DefiPositionApplyGuardTests: XCTestCase {
    private var storeToken: TestContextToken!
    private var vault: Vault!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
    }

    override func tearDown() async throws {
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - LPPosition: the no-op case

    func testLPApplyWithIdenticalDtoPublishesNoChange() {
        let dto = lpDto()
        let position = LPPosition(dto, vault: vault)

        XCTAssertFalse(
            applyPublishesChange(position, dto),
            "An identical DTO must not mutate the model. SwiftData notifies without comparing, "
                + "so any blind re-assignment re-invalidates every SwiftUI reader of this position."
        )
    }

    /// The stamp has to sit INSIDE the guard. Left outside it re-notifies on its
    /// own on every call and the guard buys nothing, so this is asserted
    /// separately rather than folded into the probe above.
    func testLPApplyWithIdenticalDtoLeavesLastUpdatedUntouched() async throws {
        let dto = lpDto()
        let position = LPPosition(dto, vault: vault)
        let stampBefore = position.lastUpdated

        // Enough of a gap that a re-stamp would be unambiguous rather than a
        // sub-microsecond tie.
        try await Task.sleep(for: .milliseconds(20))
        position.apply(dto)

        XCTAssertEqual(position.lastUpdated, stampBefore, "A no-op apply must not refresh lastUpdated.")
    }

    // MARK: - LPPosition: the real-update case

    func testLPApplyWithDifferingDtoWritesEveryField() async throws {
        let position = LPPosition(lpDto(), vault: vault)
        let idBefore = position.id
        let stampBefore = position.lastUpdated
        try await Task.sleep(for: .milliseconds(20))

        let updated = lpDto(
            coin1: .make(chain: .thorChain, ticker: "TCY"),
            coin1Amount: 11,
            coin2Amount: 21,
            poolName: "BTC.BTC-updated",
            poolUnits: "2000",
            apr: 0.09
        )
        XCTAssertTrue(applyPublishesChange(position, updated))

        XCTAssertEqual(position.coin1.ticker, "TCY")
        XCTAssertEqual(position.coin1Amount, 11)
        XCTAssertEqual(position.coin2Amount, 21)
        XCTAssertEqual(position.poolName, "BTC.BTC-updated")
        XCTAssertEqual(position.poolUnits, "2000")
        XCTAssertEqual(position.apr, 0.09)
        XCTAssertGreaterThan(position.lastUpdated, stampBefore, "A real update must refresh lastUpdated.")

        // apply(_:) deliberately owns neither the lookup key nor the persistent id.
        XCTAssertEqual(position.coin2, Fixture.lpCoin2)
        XCTAssertEqual(position.id, idBefore)
    }

    /// One case per field: a DTO differing in exactly that field must still be
    /// applied. Catches a field that is assigned but missing from the guard's
    /// comparison, which would make the early return swallow a real update.
    func testLPApplyPublishesChangeForEverySingleFieldDifference() {
        let cases: [(field: String, changed: (String) -> LPPositionData, verify: (LPPosition) -> Void)] = [
            ("coin1", { lpDto(coin1: .make(chain: .thorChain, ticker: "TCY"), poolName: $0) },
             { XCTAssertEqual($0.coin1.ticker, "TCY") }),
            ("coin1Amount", { lpDto(coin1Amount: 11, poolName: $0) },
             { XCTAssertEqual($0.coin1Amount, 11) }),
            ("coin2Amount", { lpDto(coin2Amount: 21, poolName: $0) },
             { XCTAssertEqual($0.coin2Amount, 21) }),
            ("poolName", { _ in lpDto(poolName: "POOL-changed") },
             { XCTAssertEqual($0.poolName, "POOL-changed") }),
            ("poolUnits", { lpDto(poolName: $0, poolUnits: "2000") },
             { XCTAssertEqual($0.poolUnits, "2000") }),
            ("apr", { lpDto(poolName: $0, apr: 0.09) },
             { XCTAssertEqual($0.apr, 0.09) })
        ]

        for (index, testCase) in cases.enumerated() {
            // `poolName` is part of the persistent id, so each case gets its own —
            // otherwise the rows collide on `@Attribute(.unique)`.
            let poolName = "POOL-\(index)"
            let position = LPPosition(lpDto(poolName: poolName), vault: vault)

            XCTAssertTrue(
                applyPublishesChange(position, testCase.changed(poolName)),
                "\(testCase.field) differs from the stored value — apply(_:) must write it"
            )
            testCase.verify(position)
        }
    }

    // MARK: - StakePosition: the no-op case

    func testStakeApplyWithIdenticalDtoPublishesNoChange() {
        let dto = stakeDto()
        let position = StakePosition(dto, vault: vault)

        XCTAssertFalse(
            applyPublishesChange(position, dto),
            "An identical DTO must not mutate the model."
        )
    }

    /// The Solana shape: `stakeAccountPubkey` already populated. The backfill
    /// branch must not re-write an equal pubkey — that write alone would notify
    /// and defeat the guard on every Solana refresh.
    func testStakeApplyWithIdenticalDtoPublishesNoChangeForSolanaRow() {
        let dto = stakeDto(
            coin: .make(chain: .solana, ticker: "SOL", decimals: 9),
            stakeAccountPubkey: "stake-account-A"
        )
        let position = StakePosition(dto, vault: vault)

        XCTAssertFalse(applyPublishesChange(position, dto))
        XCTAssertEqual(position.stakeAccountPubkey, "stake-account-A")
    }

    // MARK: - StakePosition: the real-update case

    func testStakeApplyWithDifferingDtoWritesEveryField() {
        let position = StakePosition(stakeDto(), vault: vault)
        let idBefore = position.id

        let updated = stakeDto(
            type: .compound,
            amount: 99,
            availableToUnstake: 42,
            apr: 0.9,
            estimatedReward: 7,
            nextPayout: 900,
            rewards: 8,
            rewardCoin: Fixture.stakeCoin,
            unstakeMetadata: Fixture.otherUnstakeMetadata,
            poolAddress: "pool-address-2",
            poolImplementation: "tf",
            poolName: "Pool B",
            withdrawalUnlockTime: 900,
            validatorVotePubkey: "vote-2",
            activationState: "inactive"
        )
        XCTAssertTrue(applyPublishesChange(position, updated))

        XCTAssertEqual(position.type, .compound)
        XCTAssertEqual(position.amount, 99)
        XCTAssertEqual(position.availableToUnstake, 42)
        XCTAssertEqual(position.apr, 0.9)
        XCTAssertEqual(position.estimatedReward, 7)
        XCTAssertEqual(position.nextPayout, 900)
        XCTAssertEqual(position.rewards, 8)
        XCTAssertEqual(position.rewardCoin, Fixture.stakeCoin)
        XCTAssertEqual(position.unstakeMetadata, Fixture.otherUnstakeMetadata)
        XCTAssertEqual(position.poolAddress, "pool-address-2")
        XCTAssertEqual(position.poolImplementation, "tf")
        XCTAssertEqual(position.poolName, "Pool B")
        XCTAssertEqual(position.withdrawalUnlockTime, 900)
        XCTAssertEqual(position.validatorVotePubkey, "vote-2")
        XCTAssertEqual(position.activationState, "inactive")

        // apply(_:) deliberately owns neither the lookup key nor the persistent id.
        XCTAssertEqual(position.coin, Fixture.stakeCoin)
        XCTAssertEqual(position.id, idBefore)
    }

    /// One case per field `StakePosition.apply(_:)` assigns, including the
    /// non-nil → nil transitions a comparison could otherwise miss.
    func testStakeApplyPublishesChangeForEverySingleFieldDifference() {
        let cases: [(field: String, changed: (CoinMeta) -> StakePositionData, verify: (StakePosition) -> Void)] = [
            ("type", { stakeDto(coin: $0, type: .index) },
             { XCTAssertEqual($0.type, .index) }),
            ("amount", { stakeDto(coin: $0, amount: 99) },
             { XCTAssertEqual($0.amount, 99) }),
            ("availableToUnstake", { stakeDto(coin: $0, availableToUnstake: 42) },
             { XCTAssertEqual($0.availableToUnstake, 42) }),
            ("availableToUnstake→nil", { stakeDto(coin: $0, availableToUnstake: nil) },
             { XCTAssertNil($0.availableToUnstake) }),
            ("apr", { stakeDto(coin: $0, apr: 0.9) },
             { XCTAssertEqual($0.apr, 0.9) }),
            ("estimatedReward", { stakeDto(coin: $0, estimatedReward: 7) },
             { XCTAssertEqual($0.estimatedReward, 7) }),
            ("nextPayout", { stakeDto(coin: $0, nextPayout: 900) },
             { XCTAssertEqual($0.nextPayout, 900) }),
            ("rewards", { stakeDto(coin: $0, rewards: 8) },
             { XCTAssertEqual($0.rewards, 8) }),
            ("rewards→nil", { stakeDto(coin: $0, rewards: nil) },
             { XCTAssertNil($0.rewards) }),
            ("rewardCoin", { stakeDto(coin: $0, rewardCoin: Fixture.stakeCoin) },
             { XCTAssertEqual($0.rewardCoin, Fixture.stakeCoin) }),
            ("unstakeMetadata", { stakeDto(coin: $0, unstakeMetadata: Fixture.otherUnstakeMetadata) },
             { XCTAssertEqual($0.unstakeMetadata, Fixture.otherUnstakeMetadata) }),
            ("poolAddress", { stakeDto(coin: $0, poolAddress: "pool-address-2") },
             { XCTAssertEqual($0.poolAddress, "pool-address-2") }),
            ("poolImplementation", { stakeDto(coin: $0, poolImplementation: "tf") },
             { XCTAssertEqual($0.poolImplementation, "tf") }),
            ("poolName", { stakeDto(coin: $0, poolName: "Pool B") },
             { XCTAssertEqual($0.poolName, "Pool B") }),
            ("withdrawalUnlockTime", { stakeDto(coin: $0, withdrawalUnlockTime: 900) },
             { XCTAssertEqual($0.withdrawalUnlockTime, 900) }),
            ("withdrawalUnlockTime→nil", { stakeDto(coin: $0, withdrawalUnlockTime: nil) },
             { XCTAssertNil($0.withdrawalUnlockTime) }),
            ("validatorVotePubkey", { stakeDto(coin: $0, validatorVotePubkey: "vote-2") },
             { XCTAssertEqual($0.validatorVotePubkey, "vote-2") }),
            ("activationState", { stakeDto(coin: $0, activationState: "inactive") },
             { XCTAssertEqual($0.activationState, "inactive") })
        ]

        for (index, testCase) in cases.enumerated() {
            // `coin` is part of the persistent id and is never written by
            // apply(_:), so it is the safe per-case discriminator.
            let coin = CoinMeta.make(chain: .thorChain, ticker: "STK\(index)")
            let position = StakePosition(stakeDto(coin: coin), vault: vault)

            XCTAssertTrue(
                applyPublishesChange(position, testCase.changed(coin)),
                "\(testCase.field) differs from the stored value — apply(_:) must write it"
            )
            testCase.verify(position)
        }
    }

    // MARK: - StakePosition: the stakeAccountPubkey backfill

    /// A row persisted by an older build carries the pubkey in its `id` suffix but
    /// a nil field. The guard must not stop the heal.
    func testStakeApplyBackfillsMissingStakeAccountPubkey() {
        let solMeta = CoinMeta.make(chain: .solana, ticker: "SOL", decimals: 9)
        let position = StakePosition(stakeDto(coin: solMeta, stakeAccountPubkey: nil), vault: vault)
        XCTAssertNil(position.stakeAccountPubkey)

        // Same DTO in every other respect: the backfill alone has to carry it past
        // the guard.
        let dto = stakeDto(coin: solMeta, stakeAccountPubkey: "stake-account-A")
        XCTAssertTrue(applyPublishesChange(position, dto))
        XCTAssertEqual(position.stakeAccountPubkey, "stake-account-A")
    }

    /// A populated pubkey is never rewritten — pre-existing behaviour the guard
    /// must preserve. The rest of the DTO still applies.
    func testStakeApplyKeepsExistingStakeAccountPubkey() {
        let solMeta = CoinMeta.make(chain: .solana, ticker: "SOL", decimals: 9)
        let position = StakePosition(
            stakeDto(coin: solMeta, stakeAccountPubkey: "stake-account-A"),
            vault: vault
        )

        let dto = stakeDto(coin: solMeta, amount: 77, stakeAccountPubkey: "stake-account-B")
        XCTAssertTrue(applyPublishesChange(position, dto))

        XCTAssertEqual(position.stakeAccountPubkey, "stake-account-A", "A non-nil pubkey is never rewritten.")
        XCTAssertEqual(position.amount, 77)
    }

    // MARK: - BondPosition upsert: the no-op case

    /// Bond has no `apply(_:)` — the fields are copied inline by the service, so
    /// this is the same defect in a different shape and is asserted through the
    /// real `upsert` call.
    func testBondUpsertWithIdenticalPositionPublishesNoChange() throws {
        try DefiPositionsStorageService().upsert([bondPosition(vault: vault)], for: vault)
        let persisted = try XCTUnwrap(vault.bondPositions.first)

        let published = try upsertPublishesChange(
            [bondPosition(vault: vault)],
            for: vault,
            observing: persisted
        )

        XCTAssertFalse(
            published,
            "An identical bond position must not mutate the persisted row. SwiftData notifies "
                + "without comparing, so blind re-assignment re-invalidates every SwiftUI reader."
        )
    }

    // MARK: - BondPosition upsert: the real-update case

    func testBondUpsertWithDifferingPositionWritesEveryField() throws {
        try DefiPositionsStorageService().upsert([bondPosition(vault: vault)], for: vault)
        let persisted = try XCTUnwrap(vault.bondPositions.first)
        let idBefore = persisted.id

        let published = try upsertPublishesChange(
            [bondPosition(amount: 999, apy: 0.99, nextReward: 77, nextChurn: Fixture.otherChurnDate, vault: vault)],
            for: vault,
            observing: persisted
        )

        XCTAssertTrue(published)
        XCTAssertEqual(persisted.amount, 999)
        XCTAssertEqual(persisted.apy, 0.99)
        XCTAssertEqual(persisted.nextReward, 77)
        XCTAssertEqual(persisted.nextChurn, Fixture.otherChurnDate)

        // The upsert updates in place — same row, same id, no duplicate inserted.
        XCTAssertEqual(vault.bondPositions.count, 1)
        XCTAssertEqual(persisted.id, idBefore)
    }

    /// One case per field the upsert assigns, including `nextChurn` going nil.
    ///
    /// Cases are separated by NODE, not by vault: `TestStore.makeVault(pubKey:)`
    /// varies only `name`/`pubKeyECDSA` and hardcodes `pubKeyEdDSA`, which is also
    /// `@Attribute(.unique)` — so per-case vaults would be collapsed into one row
    /// by SwiftData's silent unique-attribute upsert and the isolation would be an
    /// illusion. A distinct node address gives each case its own bond `id` inside
    /// the single fixture vault instead.
    func testBondUpsertPublishesChangeForEverySingleFieldDifference() throws {
        let cases: [(field: String, changed: (BondNode, Vault) -> BondPosition, verify: (BondPosition) -> Void)] = [
            ("amount", { bondPosition(node: $0, amount: 999, vault: $1) },
             { XCTAssertEqual($0.amount, 999) }),
            ("apy", { bondPosition(node: $0, apy: 0.99, vault: $1) },
             { XCTAssertEqual($0.apy, 0.99) }),
            ("nextReward", { bondPosition(node: $0, nextReward: 77, vault: $1) },
             { XCTAssertEqual($0.nextReward, 77) }),
            ("nextChurn", { bondPosition(node: $0, nextChurn: Fixture.otherChurnDate, vault: $1) },
             { XCTAssertEqual($0.nextChurn, Fixture.otherChurnDate) }),
            ("nextChurn→nil", { bondPosition(node: $0, nextChurn: nil, vault: $1) },
             { XCTAssertNil($0.nextChurn) })
        ]

        for (index, testCase) in cases.enumerated() {
            // The upsert's delete-stale pass drops every row absent from the
            // input, so each iteration removes the previous case's row. That is
            // harmless because no earlier row is read again — but it is why the
            // cases must not share a node address.
            let node = BondNode(coin: Fixture.bondCoin, address: "thor1node-\(index)", state: .active)
            try DefiPositionsStorageService().upsert([bondPosition(node: node, vault: vault)], for: vault)
            let persisted = try XCTUnwrap(vault.bondPositions.first { $0.node.address == node.address })

            let published = try upsertPublishesChange(
                [testCase.changed(node, vault)],
                for: vault,
                observing: persisted
            )

            XCTAssertTrue(
                published,
                "\(testCase.field) differs from the stored value — upsert must write it"
            )
            testCase.verify(persisted)
        }
    }

    // MARK: - BondPosition upsert: insert and delete-stale still work

    /// The guard restructured `if let existing … else insert` into
    /// `guard let existing else { insert; continue }`, so the insert branch is
    /// pinned explicitly.
    func testBondUpsertInsertsPositionWithNoPersistedRow() throws {
        try DefiPositionsStorageService().upsert([bondPosition(vault: vault)], for: vault)

        XCTAssertEqual(vault.bondPositions.count, 1)
        XCTAssertEqual(vault.bondPositions.first?.amount, 100)
    }

    func testBondUpsertDeletesRowsAbsentFromInput() throws {
        let nodeA = BondNode(coin: Fixture.bondCoin, address: "thor1nodeA", state: .active)
        let nodeB = BondNode(coin: Fixture.bondCoin, address: "thor1nodeB", state: .active)
        try DefiPositionsStorageService().upsert(
            [bondPosition(node: nodeA, vault: vault), bondPosition(node: nodeB, vault: vault)],
            for: vault
        )
        XCTAssertEqual(vault.bondPositions.count, 2)

        try DefiPositionsStorageService().upsert([bondPosition(node: nodeA, vault: vault)], for: vault)

        XCTAssertEqual(vault.bondPositions.count, 1, "Bond upsert deletes rows absent from the input.")
        XCTAssertEqual(vault.bondPositions.first?.node.address, "thor1nodeA")
    }
}
