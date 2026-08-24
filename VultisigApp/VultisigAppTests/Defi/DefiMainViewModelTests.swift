//
//  DefiMainViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

@MainActor
final class DefiMainViewModelTests: XCTestCase {
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

    func testChainsUseDisplayedDefiTotalAndRegroupAfterPositionChange() throws {
        let solana = makeCoin(chain: .solana, ticker: "SOL", decimals: 9, priceProviderID: "solana")
        let tron = makeCoin(chain: .tron, ticker: "TRX", decimals: 6, priceProviderID: "tron")
        tron.stakedBalance = "24000000"
        vault.coins = [solana, tron]
        vault.defiChains = [.solana, .tron]

        try RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: "usd-coin", value: 1),
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: "tron", value: 0.5)
        ])
        try enableKaminoPosition(tokenBaseUnits: 11_000_000)

        let viewModel = DefiMainViewModel()
        viewModel.groupChains(vault: vault)
        XCTAssertEqual(viewModel.filteredItems(in: vault), [.chain(.tron), .chain(.solana)])

        tron.stakedBalance = "8000000"
        viewModel.groupChains(vault: vault)

        XCTAssertEqual(
            vault.coins(for: .solana).totalDefiBalanceInFiatDecimal,
            .zero,
            "Kamino is stored outside the wallet coin balance used by the previous ordering."
        )
        XCTAssertEqual(viewModel.filteredItems(in: vault), [.chain(.solana), .chain(.tron)])
    }

    func testEqualBalancesKeepCanonicalChainOrder() {
        let solana = makeCoin(chain: .solana, ticker: "SOL", decimals: 9, priceProviderID: "solana")
        let tron = makeCoin(chain: .tron, ticker: "TRX", decimals: 6, priceProviderID: "tron")
        vault.coins = [tron, solana]
        vault.defiChains = [.tron, .solana]

        let viewModel = DefiMainViewModel()
        viewModel.groupChains(vault: vault)

        let expected = [Chain.solana, .tron].sorted { $0.index < $1.index }.map(DefiMainItem.chain)
        XCTAssertEqual(viewModel.filteredItems(in: vault), expected)
    }

    private func makeCoin(
        chain: Chain,
        ticker: String,
        decimals: Int,
        priceProviderID: String
    ) -> Coin {
        let coin = Coin(
            asset: CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals),
            address: "test-address-\(ticker)",
            hexPublicKey: ""
        )
        coin.priceProviderId = priceProviderID
        return coin
    }

    private func enableKaminoPosition(tokenBaseUnits: Int) throws {
        let descriptor = KaminoVaultRegistry.steakhouseUSDC
        let storage = KaminoPositionStorageService()
        try storage.setEnabled(true, descriptor: descriptor, for: vault)
        try storage.upsert(
            snapshots: [
                KaminoPositionSnapshot(
                    vaultAddress: descriptor.address,
                    shares: KaminoShareAmount(baseUnits: 1, decimals: descriptor.sharesDecimals),
                    tokenAmount: KaminoTokenAmount(
                        baseUnits: BigInt(tokenBaseUnits),
                        decimals: descriptor.tokenDecimals
                    ),
                    apy30d: nil,
                    pnlToken: nil
                )
            ],
            for: vault
        )
    }
}

final class DefiPositionOrderingTests: XCTestCase {
    private struct Row: Equatable {
        let id: String
        let value: Decimal
    }

    func testOrdersValuesDescending() {
        let rows = [
            Row(id: "middle", value: 5),
            Row(id: "lowest", value: 1),
            Row(id: "highest", value: 10)
        ]

        let sorted = DefiPositionOrdering.descending(rows, value: \.value, tieBreak: \.id)

        XCTAssertEqual(sorted.map(\.id), ["highest", "middle", "lowest"])
    }

    func testUsesTieBreakForEqualValues() {
        let rows = [Row(id: "second", value: 5), Row(id: "first", value: 5)]

        let sorted = DefiPositionOrdering.descending(rows, value: \.value, tieBreak: \.id)

        XCTAssertEqual(sorted.map(\.id), ["first", "second"])
    }
}
