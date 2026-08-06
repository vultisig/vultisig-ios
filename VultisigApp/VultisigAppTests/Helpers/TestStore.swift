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
            DatabaseRate.self,
            CustomRPCOverride.self,
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
    static func makeVault(pubKey: String = "test-pub-ecdsa") -> Vault {
        let vault = Vault(
            name: "Test Vault \(pubKey)",
            signers: [],
            pubKeyECDSA: pubKey,
            pubKeyEdDSA: "test-pub-eddsa",
            keyshares: [],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
        Storage.shared.modelContext.insert(vault)
        return vault
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
