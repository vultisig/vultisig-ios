//
//  TonJettonFinderTests.swift
//  VultisigAppTests
//

import XCTest
@testable import VultisigApp

final class TonJettonFinderTests: XCTestCase {

    private func finder(
        pages: [ScriptedJettonHTTPClient.Step],
        registryScript: [ScriptedJettonHTTPClient.Step] = [
            .success(TonJettonFixtures.tonAssetsWhitelist)
        ],
        pageSize: Int = TonJettonFinder.defaultPageSize,
        maxPages: Int = TonJettonFinder.defaultMaxPages
    ) -> (finder: TonJettonFinder, pageClient: ScriptedJettonHTTPClient) {
        let pageClient = ScriptedJettonHTTPClient(script: pages)
        let (store, _) = TonJettonFixtures.store(script: registryScript)
        let finder = TonJettonFinder(
            httpClient: pageClient,
            registryStore: store,
            host: URL(string: "https://test.local")!,
            pageSize: pageSize,
            maxPages: maxPages
        )
        return (finder, pageClient)
    }

    private func discover(
        pages: [ScriptedJettonHTTPClient.Step],
        registryScript: [ScriptedJettonHTTPClient.Step] = [
            .success(TonJettonFixtures.tonAssetsWhitelist)
        ],
        pageSize: Int = TonJettonFinder.defaultPageSize,
        maxPages: Int = TonJettonFinder.defaultMaxPages
    ) async throws -> [CoinMeta] {
        let (finder, _) = finder(pages: pages, registryScript: registryScript, pageSize: pageSize, maxPages: maxPages)
        return try await finder.discover(ownerAddress: TonJettonFixtures.owner)
    }

    // MARK: - What is and is not discovered

    func testOnlyVerifiedHeldJettonsAreDiscovered() async throws {
        let coins = try await discover(pages: [.success(TonJettonFixtures.ownerJettonWalletsPage)])
        XCTAssertEqual(Set(coins.map(\.ticker)), ["USDT", "NOT", "DOGS"])
    }

    /// The airdropped counterfeit in the fixture calls itself `USD₮` / "Tether
    /// USD" from an unlisted contract and reports `is_scam: false`. It must not
    /// reach the wallet.
    func testCounterfeitTetherIsNotDiscovered() async throws {
        let coins = try await discover(pages: [.success(TonJettonFixtures.ownerJettonWalletsPage)])
        XCTAssertFalse(
            coins.contains { $0.contractAddress == TonJettonAddress.canonical(TonJettonFixtures.unlistedMasterRaw) },
            "A counterfeit must never auto-appear"
        )
        XCTAssertEqual(coins.filter { $0.ticker == "USDT" }.count, 1, "Exactly one USDT, and it is the real one")
    }

    func testUnverifiedJettonIsNotDiscovered() async throws {
        let coins = try await discover(pages: [.success(TonJettonFixtures.ownerJettonWalletsPage)])
        XCTAssertFalse(coins.contains { $0.ticker == "MMM" })
    }

    func testZeroBalanceJettonIsNotDiscovered() async throws {
        let coins = try await discover(pages: [.success(TonJettonFixtures.ownerJettonWalletsPage)])
        XCTAssertFalse(coins.contains { $0.ticker == "jUSDT" }, "Whitelisted, but the account holds none")
    }

    /// The proxy has been seen returning rows it was not asked for, so the
    /// owner is checked again on our side. STON is verified and would otherwise
    /// be added to a vault that does not hold it.
    func testRowsOwnedBySomebodyElseAreDropped() async throws {
        let coins = try await discover(pages: [.success(TonJettonFixtures.ownerJettonWalletsPage)])
        XCTAssertFalse(coins.contains { $0.ticker == "STON" })
    }

    // MARK: - Metadata

    /// Curated wins outright: the chain and the whitelist both call this jetton
    /// `USD₮`, and neither publishes its decimals. Taking the on-chain symbol
    /// here would also hand a non-ASCII ticker to the discovery spam gate.
    func testCuratedMetadataWinsForTether() async throws {
        let coins = try await discover(pages: [.success(TonJettonFixtures.ownerJettonWalletsPage)])
        let usdt = try XCTUnwrap(coins.first { $0.ticker == "USDT" })

        XCTAssertEqual(usdt.decimals, 6)
        XCTAssertEqual(usdt.priceProviderId, "tether")
        XCTAssertEqual(usdt.logo, "usdt")
        XCTAssertEqual(usdt.contractAddress, TonJettonAddress.canonical(TonJettonFixtures.usdtMasterFriendly))
        XCTAssertFalse(usdt.isNativeToken)
        XCTAssertEqual(usdt.chain, .ton)
    }

    /// A whitelist-only jetton takes its display metadata from the indexer entry
    /// that rode along in the same listing — no follow-up call per jetton.
    func testWhitelistOnlyJettonTakesToncenterMetadata() async throws {
        let coins = try await discover(pages: [.success(TonJettonFixtures.ownerJettonWalletsPage)])
        let dogs = try XCTUnwrap(coins.first { $0.ticker == "DOGS" })

        XCTAssertEqual(dogs.decimals, 9)
        XCTAssertEqual(dogs.logo, TonJettonFixtures.dogsLogo, "and from the master entry, not the wallet one")
    }

    /// The discovered contract address has to be the form the vault already
    /// stores, or a discovered jetton would not dedup against a held coin.
    func testDiscoveredContractAddressesAreCanonical() async throws {
        let coins = try await discover(pages: [.success(TonJettonFixtures.ownerJettonWalletsPage)])
        for coin in coins {
            XCTAssertEqual(coin.contractAddress, TonJettonAddress.canonical(coin.contractAddress))
        }
    }

    /// A jetton balance can exceed `UInt64`; parsing it narrowly would read a
    /// real holding as zero and silently drop it.
    func testBalancesBeyondUInt64AreHeld() async throws {
        let coins = try await discover(pages: [.success(TonJettonFixtures.ownerJettonWalletsPage)])
        XCTAssertTrue(coins.contains { $0.ticker == "NOT" })
    }

    // MARK: - Paging

    func testAShortPageEndsTheWalk() async throws {
        let (finder, client) = finder(pages: [.success(TonJettonFixtures.pageOfOne)], pageSize: 2)
        _ = try await finder.discover(ownerAddress: TonJettonFixtures.owner)
        XCTAssertEqual(client.attempts, 1)
    }

    func testAFullPageIsFollowedByTheNext() async throws {
        let (finder, client) = finder(
            pages: [.success(TonJettonFixtures.pageOfTwo), .success(TonJettonFixtures.pageOfOne)],
            pageSize: 2
        )
        let coins = try await finder.discover(ownerAddress: TonJettonFixtures.owner)

        XCTAssertEqual(client.attempts, 2)
        XCTAssertEqual(Set(coins.map(\.ticker)), ["USDT", "NOT", "DOGS"])
    }

    /// A proxy that ignores `offset` replays page one forever. An owner holds
    /// exactly one wallet per master, so a page that adds no new master is the
    /// end of the list however the proxy chose to express it — without this the
    /// same balance would be walked until the page cap.
    func testAReplayedPageEndsTheWalk() async throws {
        let (finder, client) = finder(pages: [.success(TonJettonFixtures.pageOfTwo)], pageSize: 2, maxPages: 20)
        let coins = try await finder.discover(ownerAddress: TonJettonFixtures.owner)

        XCTAssertEqual(client.attempts, 2, "One page, then one that proves it repeated")
        XCTAssertEqual(coins.map(\.ticker).sorted(), ["NOT", "USDT"], "and nothing is discovered twice")
    }

    func testAnEmptyAccountDiscoversNothing() async throws {
        let coins = try await discover(pages: [.success(TonJettonFixtures.emptyPage)])
        XCTAssertTrue(coins.isEmpty)
    }

    // MARK: - Failure

    func testListingFailurePropagates() async {
        let (finder, _) = finder(pages: [.failure])
        do {
            _ = try await finder.discover(ownerAddress: TonJettonFixtures.owner)
            XCTFail("A listing that cannot be read is a discovery failure, not an empty account")
        } catch {
            // expected
        }
    }

    /// An unreachable whitelist is not a discovery failure: the curated list
    /// still recognises Tether, and the jettons only the whitelist knows about
    /// simply stop being auto-added until it comes back.
    func testRegistryOutageStillDiscoversCuratedJettons() async throws {
        let coins = try await discover(
            pages: [.success(TonJettonFixtures.ownerJettonWalletsPage)],
            registryScript: [.failure]
        )
        XCTAssertEqual(coins.map(\.ticker), ["USDT"])
    }

    func testAnUnusableOwnerAddressDiscoversNothingWithoutCallingOut() async throws {
        let (finder, client) = finder(pages: [.success(TonJettonFixtures.ownerJettonWalletsPage)])
        let coins = try await finder.discover(ownerAddress: "not-an-address")

        XCTAssertTrue(coins.isEmpty)
        XCTAssertEqual(client.attempts, 0)
    }
}
