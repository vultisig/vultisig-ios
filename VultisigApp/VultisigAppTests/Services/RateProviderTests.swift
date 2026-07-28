//
//  RateProviderTests.swift
//  VultisigAppTests
//
//  Pins the semantics of `RateProvider`'s in-memory cache after it moved from a
//  `Set<Rate>` + `first(where:)` linear scan to a `[String: Rate]` keyed by
//  `Rate.id`. The lookup is on the path of every fiat render in the app, so the
//  observable behaviour — newest-wins merge, untouched neighbours,
//  case-insensitive identifiers — has to be identical.
//
//  `RateProvider.shared` is a singleton whose in-memory cache is process-wide,
//  so every test here keys its rates off a UUID to stay isolated from its
//  neighbours. `save(rates:)` also persists, so the class installs an in-memory
//  `ModelContainer` and restores the previous one rather than writing junk rates
//  into the test host's on-disk store.
//

import Foundation
import XCTest
@testable import VultisigApp

@MainActor
final class RateProviderTests: XCTestCase {

    private var storeToken: TestContextToken?

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    /// A saved rate must be resolvable through `rate(for:)` for a coin whose
    /// `priceProviderId` matches the crypto side of the identifier.
    func testSaveRates_thenLookupByCoinMeta_returnsTheRate() throws {
        let providerId = uniqueProviderId()
        let meta = makeMeta(priceProviderId: providerId)

        try RateProvider.shared.save(rates: [makeRate(crypto: providerId, value: 1_234)])

        XCTAssertEqual(RateProvider.shared.rate(for: meta)?.value, 1_234)
        XCTAssertTrue(RateProvider.shared.hasRate(for: meta))
    }

    /// The merge is newest-wins: a later save for the same identifier replaces
    /// the cached value rather than coexisting with it. Under the previous
    /// `Set<Rate>` storage this was the point of the
    /// `filter { !newRateIds.contains(...) }.union(...)` dance, because `Rate`
    /// hashes on `id` *and* `value` — two rates with the same identifier and
    /// different values were distinct set members.
    func testSaveRates_newerRateReplacesTheCachedOneForTheSameIdentifier() throws {
        let providerId = uniqueProviderId()
        let meta = makeMeta(priceProviderId: providerId)

        try RateProvider.shared.save(rates: [makeRate(crypto: providerId, value: 10)])
        try RateProvider.shared.save(rates: [makeRate(crypto: providerId, value: 20)])

        XCTAssertEqual(RateProvider.shared.rate(for: meta)?.value, 20,
                       "The newest rate for an identifier must win")
    }

    /// Duplicate identifiers inside a single batch resolve to the last one.
    ///
    /// This is the one case the keyed cache *defines* rather than preserves:
    /// under `Set<Rate>` (hashing on id *and* value) the duplicates were
    /// distinct members and `first(where:)` returned an unspecified one. No
    /// producer emits duplicate identifiers today; pinning last-wins here means
    /// the resolution is deterministic if one ever does.
    func testSaveRates_duplicateIdentifiersInOneBatch_lastOneWins() throws {
        let providerId = uniqueProviderId()
        let meta = makeMeta(priceProviderId: providerId)

        try RateProvider.shared.save(rates: [
            makeRate(crypto: providerId, value: 1),
            makeRate(crypto: providerId, value: 2),
            makeRate(crypto: providerId, value: 3)
        ])

        XCTAssertEqual(RateProvider.shared.rate(for: meta)?.value, 3)
    }

    /// A save must only touch the identifiers it carries.
    func testSaveRates_leavesUnrelatedIdentifiersIntact() throws {
        let keptId = uniqueProviderId()
        let replacedId = uniqueProviderId()
        let keptMeta = makeMeta(priceProviderId: keptId)
        let replacedMeta = makeMeta(priceProviderId: replacedId)

        try RateProvider.shared.save(rates: [
            makeRate(crypto: keptId, value: 7),
            makeRate(crypto: replacedId, value: 8)
        ])
        try RateProvider.shared.save(rates: [makeRate(crypto: replacedId, value: 9)])

        XCTAssertEqual(RateProvider.shared.rate(for: keptMeta)?.value, 7,
                       "An unrelated cached rate must survive a save it was not part of")
        XCTAssertEqual(RateProvider.shared.rate(for: replacedMeta)?.value, 9)
    }

    /// `Rate.identifier(fiat:crypto:)` lowercases both sides, so a rate saved
    /// with an upper-cased crypto id still resolves for a coin carrying the
    /// lower-cased one. Keying the cache by `Rate.id` preserves that.
    func testRateLookup_identifierIsCaseInsensitive() throws {
        let providerId = uniqueProviderId()
        let meta = makeMeta(priceProviderId: providerId)

        try RateProvider.shared.save(rates: [makeRate(crypto: providerId.uppercased(), value: 42)])

        XCTAssertEqual(RateProvider.shared.rate(for: meta)?.value, 42)
    }

    /// An identifier that was never saved resolves to nil rather than to some
    /// other cached rate.
    func testRateLookup_unknownIdentifierReturnsNil() {
        let meta = makeMeta(priceProviderId: uniqueProviderId())

        XCTAssertNil(RateProvider.shared.rate(for: meta))
        XCTAssertFalse(RateProvider.shared.hasRate(for: meta))
    }

    // MARK: - Helpers

    /// Lower-cased so the case-insensitivity test has something to upper-case.
    private func uniqueProviderId() -> String {
        "rateprovider-test-\(UUID().uuidString.lowercased())"
    }

    private func makeRate(crypto: String, value: Double) -> Rate {
        Rate(fiat: SettingsCurrency.current.rawValue, crypto: crypto, value: value)
    }

    /// Bitcoin is deliberate: its chain type routes `RateProvider.cryptoId(for:)`
    /// down the `.priceProvider` branch, so the identifier is built from
    /// `priceProviderId` and the test controls both sides of the lookup.
    private func makeMeta(priceProviderId: String) -> CoinMeta {
        CoinMeta(
            chain: .bitcoin,
            ticker: "BTC",
            logo: "",
            decimals: 8,
            priceProviderId: priceProviderId,
            contractAddress: "",
            isNativeToken: true
        )
    }
}
