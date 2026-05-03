//
//  DefiTestStore.swift
//  VultisigAppTests
//
//  In-memory `ModelContainer` rigged into `Storage.shared` so tests can exercise
//  `DefiPositionsStorageService` and the position ViewModels without touching
//  the on-disk store.
//

import Foundation
import SwiftData
@testable import VultisigApp

/// Token returned by `DefiTestStore.installInMemoryContainer()`. Holds the previous
/// `Storage.shared.modelContext` so callers can restore it from `tearDown` (or any
/// scope-exit hook). Without this restore step the global context stays mutated after
/// the test class finishes — fine under serial XCTest, but a cross-test contamination
/// risk under parallel-test execution.
struct DefiTestContextToken {
    fileprivate let previousContext: ModelContext?
    let container: ModelContainer
}

@MainActor
enum DefiTestStore {
    /// Builds a fresh in-memory `ModelContainer` covering every `@Model` the Defi feature
    /// touches, installs its main context into `Storage.shared.modelContext`, and returns
    /// a token the caller must pass to `restore(_:)` from `tearDown` to put the previous
    /// context back.
    static func installInMemoryContainer() throws -> DefiTestContextToken {
        let previous = Storage.shared.modelContext
        let container = try makeInMemoryContainer()
        return DefiTestContextToken(previousContext: previous, container: container)
    }

    /// Restores the `Storage.shared.modelContext` saved by `installInMemoryContainer()`.
    static func restore(_ token: DefiTestContextToken) {
        Storage.shared.modelContext = token.previousContext
    }

    /// Builds an in-memory `ModelContainer` and installs its main context as
    /// `Storage.shared.modelContext`, *without* tracking the previous value. Prefer
    /// `installInMemoryContainer()` for new tests.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Vault.self,
            Coin.self,
            DefiPositions.self,
            BondPosition.self,
            StakePosition.self,
            LPPosition.self,
            CirclePosition.self,
            DatabaseRate.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        Storage.shared.modelContext = container.mainContext
        return container
    }

    /// Insert a populated Vault matching `pubKeyECDSA` so position upserts have a parent
    /// to attach via inverse relationships.
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
