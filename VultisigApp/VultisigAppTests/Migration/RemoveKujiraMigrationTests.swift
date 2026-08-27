//
//  RemoveKujiraMigrationTests.swift
//  VultisigAppTests
//

import SwiftData
import XCTest
@testable import VultisigApp

@MainActor
final class RemoveKujiraMigrationTests: XCTestCase {
    private var token: TestContextToken?

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDownWithError() throws {
        TestStore.restore(token)
        token = nil
    }

    private var kujira: CoinMeta {
        CoinMeta(
            chain: .kujira,
            ticker: "KUJI",
            logo: "kuji",
            decimals: 6,
            priceProviderId: "kujira",
            contractAddress: "",
            isNativeToken: true
        )
    }

    private var kujiraToken: CoinMeta {
        CoinMeta(
            chain: .kujira,
            ticker: "USK",
            logo: "usk",
            decimals: 6,
            priceProviderId: "usk",
            contractAddress: "factory/kujira/usk",
            isNativeToken: false
        )
    }

    private var bitcoin: CoinMeta {
        CoinMeta(
            chain: .bitcoin,
            ticker: "BTC",
            logo: "btc",
            decimals: 8,
            priceProviderId: "bitcoin",
            contractAddress: "",
            isNativeToken: true
        )
    }

    private var thorKuji: CoinMeta {
        CoinMeta(
            chain: .thorChain,
            ticker: "KUJI",
            logo: "kuji",
            decimals: 8,
            priceProviderId: "kujira",
            contractAddress: "thor.kuji",
            isNativeToken: false
        )
    }

    private var thorRkuji: CoinMeta {
        CoinMeta(
            chain: .thorChain,
            ticker: "RKUJI",
            logo: "rkuji",
            decimals: 8,
            priceProviderId: "kujira",
            contractAddress: "thor.rkuji",
            isNativeToken: false
        )
    }

    private func makeVault(pubKey: String = UUID().uuidString) -> Vault {
        let vault = Vault(
            name: "Migration Vault \(pubKey)",
            signers: [],
            pubKeyECDSA: "ecdsa-\(pubKey)",
            pubKeyEdDSA: "eddsa-\(pubKey)",
            keyshares: [],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .KeyImport
        )
        Storage.shared.modelContext.insert(vault)
        return vault
    }

    @discardableResult
    private func addCoin(_ meta: CoinMeta, to vault: Vault) -> Coin {
        let coin = Coin(asset: meta, address: "address-\(meta.ticker)", hexPublicKey: "public-key")
        coin.vault = vault
        return coin
    }

    func testRemovesNativeAndTokenKujiraCoinsButKeepsUnrelatedAndThorAssets() throws {
        let vault = makeVault()
        addCoin(kujira, to: vault)
        addCoin(kujiraToken, to: vault)
        addCoin(bitcoin, to: vault)
        addCoin(thorKuji, to: vault)
        addCoin(thorRkuji, to: vault)
        vault.defiChains = [.kujira, .thorChain]
        try Storage.shared.save()

        try RemoveKujiraMigration().migrate()

        XCTAssertFalse(vault.coins.contains { $0.chain == .kujira })
        XCTAssertEqual(Set(vault.coins.map(\.ticker)), ["BTC", "KUJI", "RKUJI"])
        XCTAssertEqual(
            Set(vault.coins.filter { $0.chain == .thorChain }.map(\.contractAddress)),
            ["thor.kuji", "thor.rkuji"]
        )
        XCTAssertEqual(vault.defiChains, [.thorChain])
    }

    func testRemovesHiddenTokensAndDefiSelectionsWithoutTickerBasedOverRemoval() throws {
        let vault = makeVault()
        HiddenToken(chain: .kujira, ticker: "USK", contractAddress: "factory/kujira/usk").vault = vault
        HiddenToken(chain: .thorChain, ticker: "KUJI", contractAddress: "thor.kuji").vault = vault
        let retiredBucket = DefiPositions(chain: .kujira, bonds: [kujira], staking: [], lps: [])
        let thorBucket = DefiPositions(
            chain: .thorChain,
            bonds: [thorKuji, kujira],
            staking: [thorRkuji, kujiraToken],
            lps: [thorKuji, kujira]
        )
        retiredBucket.vault = vault
        thorBucket.vault = vault
        try Storage.shared.save()

        try RemoveKujiraMigration().migrate()

        XCTAssertEqual(vault.hiddenTokens.map(\.chain), [Chain.thorChain.rawValue])
        XCTAssertFalse(vault.defiPositions.contains { $0.chain == .kujira })
        XCTAssertEqual(thorBucket.bonds, [thorKuji])
        XCTAssertEqual(thorBucket.staking, [thorRkuji])
        XCTAssertEqual(thorBucket.lps, [thorKuji])
    }

    func testRemovesEveryKujiraPositionCacheAndKeepsThorStake() throws {
        let vault = makeVault()
        let retiredStake = StakePosition(coin: kujira, type: .stake, amount: 1, vault: vault)
        let mixedRewardStake = StakePosition(
            coin: thorKuji,
            type: .stake,
            amount: 2,
            rewardCoin: kujira,
            vault: vault
        )
        let retainedStake = StakePosition(coin: thorRkuji, type: .stake, amount: 3, vault: vault)
        let retiredLP = LPPosition(
            coin1: thorKuji,
            coin1Amount: 1,
            coin2: kujira,
            coin2Amount: 1,
            poolName: "THOR.KUJI-KUJI.KUJI",
            poolUnits: "1",
            apr: 0,
            vault: vault
        )
        let retiredBond = BondPosition(
            node: BondNode(coin: kujira, address: "kujira1node", state: .active),
            amount: 1,
            apy: 0,
            nextReward: 0,
            vault: vault
        )
        Storage.shared.insert([retiredStake, mixedRewardStake, retainedStake])
        Storage.shared.insert(retiredLP)
        Storage.shared.insert(retiredBond)
        try Storage.shared.save()

        try RemoveKujiraMigration().migrate()

        let stakes = try Storage.shared.modelContext.fetch(FetchDescriptor<StakePosition>())
        XCTAssertEqual(stakes.map { $0.coin.contractAddress }, ["thor.rkuji"])
        XCTAssertTrue(try Storage.shared.modelContext.fetch(FetchDescriptor<LPPosition>()).isEmpty)
        XCTAssertTrue(try Storage.shared.modelContext.fetch(FetchDescriptor<BondPosition>()).isEmpty)
    }

    func testRemovesKujiraPendingTransactionsAndCustomRPCOnly() throws {
        Storage.shared.insert(StoredPendingTransaction(
            txHash: "kujira-pending",
            chain: .kujira,
            estimatedTime: "unknown"
        ))
        Storage.shared.insert(StoredPendingTransaction(
            txHash: "bitcoin-pending",
            chain: .bitcoin,
            estimatedTime: "10 minutes"
        ))
        Storage.shared.insert(CustomRPCOverride(chainRaw: Chain.kujira.rawValue, url: "https://retired.invalid"))
        Storage.shared.insert(CustomRPCOverride(chainRaw: Chain.ethereum.rawValue, url: "https://ethereum.example"))
        try Storage.shared.save()

        try RemoveKujiraMigration().migrate()

        XCTAssertEqual(
            try Storage.shared.modelContext.fetch(FetchDescriptor<StoredPendingTransaction>()).map(\.chain),
            [.bitcoin]
        )
        XCTAssertEqual(
            try Storage.shared.modelContext.fetch(FetchDescriptor<CustomRPCOverride>()).map(\.chainRaw),
            [Chain.ethereum.rawValue]
        )
    }

    func testPreservesCompatibilityKeysAddressBookAndHistory() throws {
        let vault = makeVault()
        ChainPublicKey(chain: .kujira, publicKeyHex: "legacy-kujira-key", isEddsa: false).vault = vault
        let address = AddressBookItem(title: "Historical Kujira", address: "kujira1legacy", coinMeta: kujira, order: 0)
        let history = TransactionHistoryItem(
            txHash: "historical-kujira-transaction",
            pubKeyECDSA: vault.pubKeyECDSA,
            typeRawValue: "send",
            statusRawValue: "confirmed",
            chainRawValue: Chain.kujira.rawValue,
            coinTicker: "KUJI",
            coinLogo: "kuji",
            amountCrypto: "1 KUJI",
            amountFiat: "$0",
            fromAddress: "kujira1from",
            toAddress: "kujira1to",
            feeCrypto: "0.001 KUJI",
            feeFiat: "$0",
            network: "Kujira",
            explorerLink: ""
        )
        Storage.shared.insert(address)
        Storage.shared.insert(history)
        try Storage.shared.save()

        try RemoveKujiraMigration().migrate()

        XCTAssertEqual(vault.chainPublicKeys.map(\.chain), [.kujira])
        XCTAssertEqual(try Storage.shared.modelContext.fetch(FetchDescriptor<AddressBookItem>()).map(\.id), [address.id])
        XCTAssertEqual(
            try Storage.shared.modelContext.fetch(FetchDescriptor<TransactionHistoryItem>()).map(\.txHash),
            [history.txHash]
        )
    }

    func testRunningMigrationTwiceIsANoOp() throws {
        let vault = makeVault()
        addCoin(kujira, to: vault)
        addCoin(thorKuji, to: vault)
        try Storage.shared.save()

        try RemoveKujiraMigration().migrate()
        let retainedIDs = vault.coins.map(\.id)

        try RemoveKujiraMigration().migrate()

        XCTAssertEqual(vault.coins.map(\.id), retainedIDs)
        XCTAssertEqual(vault.coins.map(\.contractAddress), ["thor.kuji"])
    }

    func testLegacyKujiraIdentityStillDecodesBeforeCleanup() throws {
        let decoded = try JSONDecoder().decode(Chain.self, from: Data("\"kujira\"".utf8))

        XCTAssertEqual(decoded, .kujira)
    }

    func testMigrationServiceRegistersVersionSixAfterVersionFive() throws {
        let vault = makeVault()
        addCoin(kujira, to: vault)
        try Storage.shared.save()
        let previousVersion = StakePositionCeilingMigration().version
        let keychain = MockKeychainService(lastMigratedVersion: previousVersion)

        AppMigrationService(keychainService: keychain).performMigrationsIfNeeded()

        XCTAssertEqual(previousVersion, 5)
        XCTAssertEqual(RemoveKujiraMigration().version, 6)
        XCTAssertFalse(vault.coins.contains { $0.chain == .kujira })
        XCTAssertEqual(keychain.lastMigratedVersion, 6)
    }
}
