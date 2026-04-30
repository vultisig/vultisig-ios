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

/// Boots an in-memory ModelContainer covering every `@Model` the Defi feature touches and
/// installs its main context into `Storage.shared.modelContext`. Returns the container so
/// tests can keep it alive (the context is a weak reference inside SwiftData).
@MainActor
enum DefiTestStore {
    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Vault.self,
            Coin.self,
            DefiPositions.self,
            BondPosition.self,
            StakePosition.self,
            LPPosition.self,
            CirclePosition.self
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
