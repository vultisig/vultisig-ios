//
//  RateProviderWriteGuardTests.swift
//  VultisigAppTests
//
//  `RateProvider.save(rates:)` must leave a persisted `DatabaseRate` untouched
//  when the refreshed rate already matches it.
//
//  Asserting on the resulting VALUES cannot show that — a blind re-assignment of
//  an identical value leaves the values identical, so a test written that way
//  passes against the unguarded implementation too. What separates them is the
//  mutation: SwiftData's `@Model` setter routes through the Observation
//  registrar and notifies WITHOUT comparing new to old, and the `save()` that
//  follows posts a store-change notification which re-evaluates every `@Query`
//  in the app — including queries over entirely unrelated types. That is why
//  "no view reads `DatabaseRate`" does not make this site safe, and why these
//  tests observe with `withObservationTracking` and assert on whether a change
//  was published rather than on values.
//
//  The per-field sweep is the other half: a field written but not compared makes
//  the early return swallow a real update. `fiat` and `crypto` are reachable
//  because `Rate.id` lowercases both, so a differently-cased pair resolves to the
//  same persisted row.
//
//  `RateProvider` is a process-wide singleton whose in-memory cache outlives the
//  per-test model container, so — as in `RateProviderTests` — every test keys its
//  rates off a UUID and cannot contaminate another.
//

@testable import VultisigApp
import Observation
import SwiftData
import XCTest

/// Reference box so the `@Sendable` `onChange` closure can report back without
/// capturing a mutable local. Every access is main-actor and synchronous.
private final class ChangeRecorder: @unchecked Sendable {
    private(set) var didChange = false
    func record() { didChange = true }
}

@MainActor
final class RateProviderWriteGuardTests: XCTestCase {

    private var token: TestContextToken!

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(token)
        token = nil
    }

    // MARK: - Helpers

    private func changePublished(reading read: () -> Void, during mutate: () throws -> Void) rethrows -> Bool {
        let recorder = ChangeRecorder()
        withObservationTracking { read() } onChange: { recorder.record() }
        try mutate()
        return recorder.didChange
    }

    /// Reads every property the guard can write. All of them have to be observed
    /// or the probe could miss a write and the test would pass vacuously. `id` is
    /// the lookup key and is never written.
    private func readFields(_ object: DatabaseRate) {
        _ = object.fiat
        _ = object.crypto
        _ = object.value
    }

    private func storedRate(id: String) throws -> DatabaseRate {
        let descriptor = FetchDescriptor<DatabaseRate>(predicate: #Predicate { $0.id == id })
        return try XCTUnwrap(Storage.shared.modelContext.fetch(descriptor).first)
    }

    /// Keeps each test's rates out of the singleton's process-wide cache.
    private func uniqueCryptoId() -> String {
        "rate-guard-test-\(UUID().uuidString.lowercased())"
    }

    /// A coin whose `RateProvider.cryptoId` is `priceProviderId`, so the cache
    /// can be read back through the same lookup the app uses.
    private func makeCoin(priceProviderId: String) -> CoinMeta {
        CoinMeta(
            chain: .bitcoin,
            ticker: "TST",
            logo: "",
            decimals: 8,
            priceProviderId: priceProviderId,
            contractAddress: "",
            isNativeToken: true
        )
    }

    // MARK: - The no-op case

    func testSavingAnIdenticalRatePublishesNoChange() throws {
        let rate = Rate(fiat: "usd", crypto: uniqueCryptoId(), value: 42)
        try RateProvider.shared.save(rates: [rate])
        let stored = try storedRate(id: rate.id)

        let published = try changePublished(reading: { readFields(stored) }, during: {
            try RateProvider.shared.save(rates: [rate])
        })

        XCTAssertFalse(
            published,
            "An identical rate must not mutate the row. SwiftData notifies without comparing, and the save "
                + "that follows re-evaluates every @Query in the app — whatever type it queries."
        )
        XCTAssertEqual(stored.value, 42)
    }

    /// Neither a NaN nor an infinity is a usable price. NaN is additionally the
    /// one value an equality guard cannot suppress at all: `NaN != NaN`, and the
    /// attribute coerces it to `0` on persist (infinities persist as they are),
    /// so the stored value never compares equal to the incoming one and the row
    /// would be re-dirtied on every single refresh.
    func testSavingANonFiniteRateOverAStoredRatePublishesNoChange() throws {
        for value in [Double.nan, .infinity, -.infinity] {
            let crypto = uniqueCryptoId()
            try RateProvider.shared.save(rates: [Rate(fiat: "usd", crypto: crypto, value: 5)])
            let stored = try storedRate(id: Rate.identifier(fiat: "usd", crypto: crypto))

            let published = try changePublished(reading: { readFields(stored) }, during: {
                try RateProvider.shared.save(rates: [Rate(fiat: "usd", crypto: crypto, value: value)])
            })

            XCTAssertFalse(published, "\(value): a non-finite rate must not be written.")
            XCTAssertEqual(stored.value, 5, "\(value): the last usable price must survive.")
        }
    }

    /// The cache is what every fiat render reads, and it is merged before any
    /// persistence happens — so the non-finite filter has to sit ahead of it,
    /// not inside the row update.
    func testNonFiniteRateDoesNotEvictTheCachedPrice() throws {
        let providerId = uniqueCryptoId()
        let coin = makeCoin(priceProviderId: providerId)
        let fiat = SettingsCurrency.current.rawValue
        try RateProvider.shared.save(rates: [Rate(fiat: fiat, crypto: providerId, value: 5)])
        XCTAssertEqual(RateProvider.shared.rate(for: coin)?.value, 5)

        try RateProvider.shared.save(rates: [Rate(fiat: fiat, crypto: providerId, value: .nan)])

        XCTAssertEqual(
            RateProvider.shared.rate(for: coin)?.value,
            5,
            "A non-finite rate must not replace the cached price every fiat render reads."
        )
    }

    /// The insert branch is the other half the row-update guard cannot reach: a
    /// coin priced for the first time by a non-finite rate must not get a row at
    /// all, rather than a row the next refresh can never leave alone.
    func testNonFiniteRateIsNotPersistedAsANewRow() throws {
        let crypto = uniqueCryptoId()
        let id = Rate.identifier(fiat: "usd", crypto: crypto)

        try RateProvider.shared.save(rates: [Rate(fiat: "usd", crypto: crypto, value: .nan)])

        let descriptor = FetchDescriptor<DatabaseRate>(predicate: #Predicate { $0.id == id })
        XCTAssertTrue(try Storage.shared.modelContext.fetch(descriptor).isEmpty)
    }

    /// The warm-start load is the one path that could put a non-finite rate back
    /// into the cache: a build predating the filter could have persisted an
    /// infinity (NaN could not — it is coerced to `0` on save). The finite row in
    /// the same load has to survive, or the filter would be passing by loading
    /// nothing at all.
    func testWarmStartLoadsFinitePersistedRatesAndSkipsNonFiniteOnes() throws {
        let fiat = SettingsCurrency.current.rawValue
        let goodCrypto = uniqueCryptoId()
        let poisonedCrypto = uniqueCryptoId()
        Storage.shared.insert(DatabaseRate(
            id: Rate.identifier(fiat: fiat, crypto: goodCrypto), fiat: fiat, crypto: goodCrypto, value: 3
        ))
        Storage.shared.insert(DatabaseRate(
            id: Rate.identifier(fiat: fiat, crypto: poisonedCrypto),
            fiat: fiat,
            crypto: poisonedCrypto,
            value: .infinity
        ))
        try Storage.shared.save()

        RateProvider.shared.loadPersistedRates()

        XCTAssertEqual(RateProvider.shared.rate(for: makeCoin(priceProviderId: goodCrypto))?.value, 3)
        XCTAssertNil(
            RateProvider.shared.rate(for: makeCoin(priceProviderId: poisonedCrypto)),
            "A persisted non-finite rate must not reach the cache every fiat render reads."
        )
    }

    /// The guard declines only non-finite values; a real price still lands.
    func testSavingAFiniteRateAfterANonFiniteOnePublishesChange() throws {
        let crypto = uniqueCryptoId()
        try RateProvider.shared.save(rates: [Rate(fiat: "usd", crypto: crypto, value: 5)])
        let stored = try storedRate(id: Rate.identifier(fiat: "usd", crypto: crypto))
        try RateProvider.shared.save(rates: [Rate(fiat: "usd", crypto: crypto, value: .nan)])

        let published = try changePublished(reading: { readFields(stored) }, during: {
            try RateProvider.shared.save(rates: [Rate(fiat: "usd", crypto: crypto, value: 9)])
        })

        XCTAssertTrue(published, "A finite rate arriving after a rejected one is a real update.")
        XCTAssertEqual(stored.value, 9)
    }

    /// One row per coin, and a refresh usually moves only some of them. The rows
    /// that did not move must not be written just because their neighbours were.
    func testSavingABatchOnlyMutatesTheRatesThatMoved() throws {
        let stable = Rate(fiat: "usd", crypto: uniqueCryptoId(), value: 1)
        let movingCrypto = uniqueCryptoId()
        let moving = Rate(fiat: "usd", crypto: movingCrypto, value: 2)
        try RateProvider.shared.save(rates: [stable, moving])
        let stableRow = try storedRate(id: stable.id)

        let published = try changePublished(reading: { readFields(stableRow) }, during: {
            try RateProvider.shared.save(rates: [stable, Rate(fiat: "usd", crypto: movingCrypto, value: 3)])
        })

        XCTAssertFalse(published, "The unchanged rate in the batch must not be written.")
        XCTAssertEqual(try storedRate(id: moving.id).value, 3, "The changed rate still has to be written.")
    }

    // MARK: - The real-update case

    /// One case per field the guard assigns. `fiat` and `crypto` differ from the
    /// stored row while resolving to the same `Rate.id`, because the identifier
    /// lowercases both.
    func testSavePublishesChangeForEverySingleFieldDifference() throws {
        let cases: [(
            field: String,
            seed: (String) -> Rate,
            updated: (String) -> Rate,
            verify: (DatabaseRate, String) -> Void
        )] = [
            (
                "value",
                { Rate(fiat: "usd", crypto: $0, value: 1) },
                { Rate(fiat: "usd", crypto: $0, value: 9) },
                { row, _ in XCTAssertEqual(row.value, 9) }
            ),
            (
                "fiat",
                { Rate(fiat: "usd", crypto: $0, value: 1) },
                { Rate(fiat: "USD", crypto: $0, value: 1) },
                { row, _ in XCTAssertEqual(row.fiat, "USD") }
            ),
            (
                "crypto",
                { Rate(fiat: "usd", crypto: $0, value: 1) },
                { Rate(fiat: "usd", crypto: $0.uppercased(), value: 1) },
                { row, crypto in XCTAssertEqual(row.crypto, crypto.uppercased()) }
            )
        ]

        for testCase in cases {
            let crypto = uniqueCryptoId()
            let seed = testCase.seed(crypto)
            let updated = testCase.updated(crypto)
            XCTAssertEqual(seed.id, updated.id, "\(testCase.field): both must hit the same row")

            try RateProvider.shared.save(rates: [seed])
            let stored = try storedRate(id: seed.id)

            let published = try changePublished(reading: { readFields(stored) }, during: {
                try RateProvider.shared.save(rates: [updated])
            })

            XCTAssertTrue(
                published,
                "\(testCase.field) differs from the stored value — save(rates:) must write it"
            )
            testCase.verify(stored, crypto)
        }
    }

    /// A rate with no persisted row still has to be inserted; the guard only
    /// covers the update branch.
    func testSaveInsertsARateThatHasNoStoredRow() throws {
        let crypto = uniqueCryptoId()
        let rate = Rate(fiat: "usd", crypto: crypto, value: 7)

        try RateProvider.shared.save(rates: [rate])

        let stored = try storedRate(id: rate.id)
        XCTAssertEqual(stored.fiat, "usd")
        XCTAssertEqual(stored.crypto, crypto)
        XCTAssertEqual(stored.value, 7)
    }
}
