//
//  TransactionHistoryTryAgainTests.swift
//  VultisigAppTests
//
//  History resolves a row's Try again pair against the screen's own vault, and
//  only for a failed market swap; the detail sheet renders whatever it is
//  handed. The matching rules themselves are pinned in `SwapTryAgainTests`.
//

import XCTest
@testable import VultisigApp

@MainActor
final class TransactionHistoryTryAgainTests: XCTestCase {

    private static let vaultPubKey = "history-try-again-vault"

    private var token: TestContextToken?

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    func testAFailedSwapRowResolvesAgainstTheScreensVault() {
        let (usdc, btc) = makeVaultHoldingPair()
        let viewModel = makeViewModel(pubKey: Self.vaultPubKey)

        XCTAssertEqual(
            viewModel.tryAgainPair(for: makeRow(from: usdc, to: btc)),
            SwapTryAgainPair(fromCoinID: usdc.id, toCoinID: btc.id)
        )
    }

    func testOnlyAFailedSwapRowOffersAPair() {
        let (usdc, btc) = makeVaultHoldingPair()
        let viewModel = makeViewModel(pubKey: Self.vaultPubKey)

        XCTAssertNil(viewModel.tryAgainPair(for: makeRow(from: usdc, to: btc, status: .inProgress)))
        XCTAssertNil(viewModel.tryAgainPair(for: makeRow(from: usdc, to: btc, status: .successful)))
        XCTAssertNil(viewModel.tryAgainPair(for: makeRow(from: usdc, to: btc, type: .limit)))
    }

    func testAScreenWhoseVaultCannotBeFoundOffersNothing() {
        let (usdc, btc) = makeVaultHoldingPair()
        let viewModel = makeViewModel(pubKey: "no-such-vault")

        XCTAssertNil(viewModel.tryAgainPair(for: makeRow(from: usdc, to: btc)))
    }

    // MARK: - Fixtures

    private func makeViewModel(pubKey: String) -> TransactionHistoryViewModel {
        TransactionHistoryViewModel(pubKeyECDSA: pubKey, vaultName: "Test Vault", chainFilter: nil)
    }

    private func makeVaultHoldingPair() -> (usdc: Coin, btc: Coin) {
        let vault = TestStore.makeVault(pubKey: Self.vaultPubKey)
        let usdc = makeCoin(
            chain: .ethereum,
            ticker: "USDC",
            contract: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
            address: "0x7f6E1d3A4b5C6D7e8F9a0B1c2D3e4F5a6B7c8D9e"
        )
        let btc = makeCoin(chain: .bitcoin, ticker: "BTC", contract: "", address: "bc1qvaultaddress")
        vault.coins.append(contentsOf: [usdc, btc])
        return (usdc, btc)
    }

    private func makeCoin(chain: Chain, ticker: String, contract: String, address: String) -> Coin {
        Coin(
            asset: CoinMeta(
                chain: chain,
                ticker: ticker,
                logo: ticker.lowercased(),
                decimals: 8,
                priceProviderId: "",
                contractAddress: contract,
                isNativeToken: contract.isEmpty
            ),
            address: address,
            hexPublicKey: ""
        )
    }

    private func makeRow(
        from: Coin,
        to: Coin,
        type: TransactionHistoryType = .swap,
        status: TransactionHistoryStatus = .error
    ) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: "0xswap",
            approveTxHash: nil,
            pubKeyECDSA: Self.vaultPubKey,
            type: type,
            status: status,
            chainRawValue: from.chain.rawValue,
            coinTicker: from.ticker,
            coinLogo: "",
            coinChainLogo: nil,
            amountCrypto: "1",
            amountFiat: "1",
            fromAddress: from.address,
            toAddress: to.address,
            toCoinTicker: to.ticker,
            toCoinLogo: nil,
            toCoinChainLogo: nil,
            toAmountCrypto: "1",
            toAmountFiat: "1",
            swapProvider: "THORChain",
            fromContractAddress: from.contractAddress,
            toChainRawValue: to.chain.rawValue,
            toContractAddress: to.contractAddress,
            feeCrypto: "",
            feeFiat: "",
            network: "",
            explorerLink: "",
            createdAt: Date(),
            completedAt: nil,
            estimatedTime: nil,
            errorMessage: nil
        )
    }
}
