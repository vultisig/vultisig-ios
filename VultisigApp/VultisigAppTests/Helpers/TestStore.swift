//
//  TestStore.swift
//  VultisigAppTests
//
//  In-memory `ModelContainer` rigged into `Storage.shared` so any test in the
//  suite can exercise SwiftData-backed services and ViewModels without
//  touching the on-disk store. Generalized from `DefiTestStore` in §0.E so
//  the Send/Swap/Function refactors can reuse it.
//
//  Schema includes every `@Model` the test suite touches across features —
//  one shared container is simpler than per-feature containers and the
//  in-memory cost is negligible.
//

import Foundation
import SwiftData
import XCTest
@testable import VultisigApp

/// Token returned by `TestStore.installInMemoryContainer()`. Holds the previous
/// `Storage.shared.modelContext` so callers restore it from `tearDown` (or any
/// scope-exit hook). Without this restore step the global context stays mutated
/// after the test class finishes — fine under serial XCTest, but a cross-test
/// contamination risk under parallel-test execution.
struct TestContextToken {
    fileprivate let previousContext: ModelContext?
    let container: ModelContainer
}

@MainActor
enum TestStore {
    /// Builds a fresh in-memory `ModelContainer` covering every `@Model` the
    /// test suite touches, installs its main context into
    /// `Storage.shared.modelContext`, and returns a token the caller must pass
    /// to `restore(_:)` from `tearDown` to put the previous context back.
    static func installInMemoryContainer() throws -> TestContextToken {
        let previous = Storage.shared.modelContext
        let container = try makeInMemoryContainer()
        return TestContextToken(previousContext: previous, container: container)
    }

    /// Restores the `Storage.shared.modelContext` saved by `installInMemoryContainer()`.
    /// `nil`-tolerant so a `tearDown` after a thrown `setUp` doesn't trap on the
    /// IUO token and mask the real failure.
    static func restore(_ token: TestContextToken?) {
        guard let token else { return }
        Storage.shared.modelContext = token.previousContext
    }

    /// Builds an in-memory `ModelContainer` and installs its main context as
    /// `Storage.shared.modelContext`, *without* tracking the previous value.
    /// Prefer `installInMemoryContainer()` for new tests.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Vault.self,
            Coin.self,
            HiddenToken.self,
            DefiPositions.self,
            BondPosition.self,
            StakePosition.self,
            LPPosition.self,
            CirclePosition.self,
            YieldPosition.self,
            YieldRedemptionRecord.self,
            KaminoPosition.self,
            DatabaseRate.self,
            CustomRPCOverride.self,
            StoredPendingTransaction.self,
            AddressBookItem.self,
            TransactionHistoryItem.self,
            SwapTrackingMetadata.self,
            LimitOrder.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        Storage.shared.modelContext = container.mainContext
        return container
    }

    /// Containers held for the lifetime of the test process.
    private static var retained: [ModelContainer] = []

    /// Keeps a test's container alive past its `tearDown`.
    ///
    /// For tests that exercise code starting unstructured work — the token
    /// discovery `VaultDefaultCoinService.startTokenDiscovery()` hands out is
    /// the case here — which resumes after the test method returns and touches
    /// the models it resolved. Letting the container go first turns that into a
    /// trap ("this model instance was destroyed by calling ModelContext.reset")
    /// that fails whichever test happens to be running. The app's container is
    /// process-lifetime, so this makes the test resemble production rather than
    /// papering over anything.
    static func retain(_ container: ModelContainer) {
        retained.append(container)
    }

    /// The chains ``makeDerivableVault(index:keyshare:)`` derives.
    ///
    /// Both are real ECDSA chains, and both resolve to `NoTokenDiscoverer` — see
    /// the note on the fixture for why that matters. Tron is here so the DeFi
    /// chains `setDefaultCoins` derives alongside the coins are non-empty.
    static let derivableChains: [Chain] = [.bitcoin, .tron]

    /// A vault carrying real secp256k1 key material, so `CoinFactory` derives
    /// actual addresses and `setDefaultCoins` produces actual coins.
    ///
    /// Placeholder keys are not good enough for anything about default coins:
    /// `CoinFactory.create` throws on them and `compactMap` drops the failure, so
    /// a vault built that way derives nothing at all — and a test asserting on its
    /// coins passes just as happily against an import that attaches none of them.
    ///
    /// Key-import with explicit per-chain keys rather than a DKLS vault on the
    /// base default chains, so the fixture is hermetic. `setDefaultCoins` starts
    /// an unstructured token-discovery `Task` per coin which outlives the test,
    /// goes to the network, and writes through `Storage.shared` — by then the
    /// *next* test's container. Relating a row from that store to this vault
    /// traps, and it takes down the whole test host rather than one test.
    /// ``derivableChains`` have no token discoverer behind them, so nothing is
    /// fetched and nothing outlives the test.
    ///
    /// Not inserted; the caller decides when it reaches a context. `index` picks
    /// distinct key material, because `name`, `pubKeyECDSA` and `pubKeyEdDSA` are
    /// all `@Attribute(.unique)` and SwiftData answers a duplicate with an upsert
    /// rather than an error — two fixtures sharing one collapse into a single row.
    static func makeDerivableVault(index: Int = 0, keyshare: String) -> Vault {
        let ecdsa = [
            "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b",
            "0342d6eb3e536bd1d6f57a8388afb09936aa64160c5e2ebee76d791b4844a06770"
        ]
        let vault = Vault(
            name: "Derivable Vault \(index)",
            signers: [],
            pubKeyECDSA: ecdsa[index],
            pubKeyEdDSA: "eddsa-\(index)",
            keyshares: [KeyShare(pubkey: ecdsa[index], keyshare: keyshare)],
            localPartyID: "party-\(index)",
            hexChainCode: "c9b189a8232b872b8d9ccd867d0db316dd10f56e729c310fe072adf5fd204ae7",
            resharePrefix: nil,
            libType: .KeyImport
        )
        vault.chainPublicKeys = derivableChains.map {
            ChainPublicKey(chain: $0, publicKeyHex: ecdsa[index], isEddsa: false)
        }
        return vault
    }

    /// Insert a populated Vault matching `pubKeyECDSA` so position upserts have a
    /// parent to attach via inverse relationships.
    ///
    /// Every unique `String` attribute `Vault` declares — `name`, `pubKeyECDSA`
    /// and `pubKeyEdDSA` — is derived from `pubKey`, so two fixtures built with
    /// different keys are two rows. Hard-coding any one of them is not cosmetic:
    /// SwiftData answers a duplicate unique value with an **upsert**, not an
    /// error, so each insert silently replaces the last and the store ends up
    /// holding one survivor. Assertions shaped `for vault in fetch() { … }`, and
    /// any expectation about ordering or count, then pass vacuously.
    ///
    /// `publicKeyMLDSA44` is unique too and deliberately stays `nil`: a unique
    /// index treats NULLs as distinct, so nil fixtures never collapse, while
    /// giving it a value would flip every product branch that reads the field as
    /// "this is a quantum vault" — QBTC coin creation, the MLDSA keysign key,
    /// the advanced-settings gate — for callers that only wanted a parent row.
    ///
    /// Fails the calling test if the fixture would land on top of a vault
    /// already in the store, so a future hard-coded unique field cannot regress
    /// into a silent upsert.
    static func makeVault(
        pubKey: String = "test-pub-ecdsa",
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Vault {
        let vault = Vault(
            name: "Test Vault \(pubKey)",
            signers: [],
            pubKeyECDSA: pubKey,
            pubKeyEdDSA: "test-pub-eddsa-\(pubKey)",
            keyshares: [],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
        assertNoUniqueCollision(for: vault, file: file, line: line)
        Storage.shared.modelContext.insert(vault)
        return vault
    }

    /// Fails the running test when `candidate` shares a `@Attribute(.unique)`
    /// value with a vault already in `Storage.shared`.
    ///
    /// Asked *before* the insert rather than by counting rows after it. The
    /// collapse itself only lands when the context saves, so a post-insert count
    /// reads one-more even for a duplicate and would report the collision at
    /// whatever unrelated place happened to save next. A pre-insert lookup
    /// answers the precise question — is there already a row this insert would
    /// replace — and can only fire on a real collision.
    private static func assertNoUniqueCollision(
        for candidate: Vault,
        file: StaticString,
        line: UInt
    ) {
        let stored: [Vault]
        do {
            stored = try Storage.shared.modelContext.fetch(FetchDescriptor<Vault>())
        } catch {
            XCTFail("TestStore.makeVault could not read the vault store: \(error)", file: file, line: line)
            return
        }

        for existing in stored {
            var collided: [String] = []
            if existing.name == candidate.name { collided.append("name") }
            if existing.pubKeyECDSA == candidate.pubKeyECDSA { collided.append("pubKeyECDSA") }
            if existing.pubKeyEdDSA == candidate.pubKeyEdDSA { collided.append("pubKeyEdDSA") }
            // A nil MLDSA key is not a duplicate — a unique index treats NULLs
            // as distinct, which is why the fixture is allowed to leave it nil.
            if let mldsa = candidate.publicKeyMLDSA44, existing.publicKeyMLDSA44 == mldsa {
                collided.append("publicKeyMLDSA44")
            }
            guard collided.isEmpty else {
                XCTFail(
                    """
                    TestStore.makeVault(pubKey: "\(candidate.pubKeyECDSA)") duplicates a vault already \
                    in the store on \(collided.joined(separator: ", ")). SwiftData resolves a unique \
                    collision by upserting, so this insert would replace that row and leave the test \
                    asserting over a single survivor. Give each fixture its own `pubKey:`, and install \
                    a fresh in-memory container per test so nothing leaks in from the previous one.
                    """,
                    file: file,
                    line: line
                )
                return
            }
        }
    }
}

extension CoinMeta {
    static func make(chain: Chain, ticker: String, decimals: Int = 8, isNativeToken: Bool = true) -> CoinMeta {
        CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "logo",
            decimals: decimals,
            priceProviderId: ticker.lowercased(),
            contractAddress: "\(ticker)-contract",
            isNativeToken: isNativeToken
        )
    }
}
