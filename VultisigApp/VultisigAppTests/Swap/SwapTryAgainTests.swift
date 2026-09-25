//
//  SwapTryAgainTests.swift
//  VultisigAppTests
//
//  "Try again" on a failed swap reopens the swap form with the pair selected.
//  The pair is resolved against the vault's live coins, never trusted from the
//  row on its own: the form needs the exact coin, or nothing if there is any
//  doubt which one it was — a wrong guess sells the wrong asset.
//

import XCTest
@testable import VultisigApp

@MainActor
final class SwapTryAgainTests: XCTestCase {

    private static let evmAddress = "0x7f6E1d3A4b5C6D7e8F9a0B1c2D3e4F5a6B7c8D9e"
    private nonisolated static let curatedUSDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    private static let customUSDC = "0x1111111111111111111111111111111111111111"
    private static let tonJetton = "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs"

    // MARK: - Pair resolution

    func testMarketSwapRowResolvesToTheHeldPair() {
        let usdc = makeUSDC()
        let btc = makeBTC()

        let pair = SwapTryAgain.pair(for: makeRow(from: usdc, to: btc), in: [makeETH(), usdc, btc])

        XCTAssertEqual(pair, SwapTryAgainPair(fromCoinID: usdc.id, toCoinID: btc.id))
    }

    func testTheRouteCarriesThePairAndNothingElse() throws {
        let usdc = makeUSDC()
        let btc = makeBTC()
        let pair = try XCTUnwrap(SwapTryAgain.pair(for: makeRow(from: usdc, to: btc), in: [usdc, btc]))

        XCTAssertEqual(
            pair.route(vaultPubKeyECDSA: "vault-pub"),
            .root(fromCoinID: usdc.id, toCoinID: btc.id, vaultPubKeyECDSA: "vault-pub")
        )
    }

    /// Overview and History answer from the same rules, so the button the
    /// done screen offers is the one the row offers later.
    func testTheSignedSwapAndItsRowResolveTheSamePair() {
        let usdc = makeUSDC()
        let btc = makeBTC()
        let coins = [makeETH(), usdc, btc]

        let fromOverview = SwapTryAgain.pair(
            status: .failed(reason: "reverted"),
            fromCoin: usdc,
            toCoin: btc,
            isLimitOrder: false,
            in: coins
        )
        let fromHistory = SwapTryAgain.pair(for: makeRow(from: usdc, to: btc), in: coins)

        XCTAssertNotNil(fromOverview)
        XCTAssertEqual(fromOverview, fromHistory)
    }

    func testALimitOrderIsNeverTriedAgainAsAMarketSwap() {
        let usdc = makeUSDC()
        let btc = makeBTC()

        XCTAssertNil(SwapTryAgain.pair(fromCoin: usdc, toCoin: btc, isLimitOrder: true, in: [usdc, btc]))
        XCTAssertNil(SwapTryAgain.pair(for: makeRow(from: usdc, to: btc, type: .limit), in: [usdc, btc]))
    }

    func testASideTheVaultNoLongerHoldsHidesTryAgain() {
        let usdc = makeUSDC()
        let btc = makeBTC()
        let row = makeRow(from: usdc, to: btc)

        XCTAssertNil(SwapTryAgain.pair(for: row, in: [usdc]))
        XCTAssertNil(SwapTryAgain.pair(for: row, in: [btc]))
        XCTAssertNil(SwapTryAgain.pair(fromCoin: usdc, toCoin: btc, isLimitOrder: false, in: [usdc]))
    }

    func testTheContractPicksBetweenTwoSameTickerTokensOnOneChain() {
        let curated = makeUSDC(contract: Self.curatedUSDC)
        let custom = makeUSDC(contract: Self.customUSDC)
        let btc = makeBTC()

        let pair = SwapTryAgain.pair(for: makeRow(from: custom, to: btc), in: [curated, custom, btc])

        XCTAssertEqual(pair?.fromCoinID, custom.id)
    }

    /// The case a ticker-only row cannot answer: the same token on two EVM
    /// chains, held at the same address.
    func testTheSameTickerOnTwoChainsIsToldApartByChain() {
        let btc = makeBTC()
        let ethereumUSDC = makeUSDC()
        let arbitrumUSDC = makeUSDC(chain: .arbitrum)

        let pair = SwapTryAgain.pair(for: makeRow(from: btc, to: arbitrumUSDC), in: [btc, ethereumUSDC, arbitrumUSDC])

        XCTAssertEqual(pair?.toCoinID, arbitrumUSDC.id)
    }

    /// EVM contracts are compared case-folded: the same contract may be held
    /// checksummed and re-added lowercased.
    func testAnEVMContractMatchesAcrossCase() {
        let usdc = makeUSDC()
        let btc = makeBTC()
        let row = makeRow(
            from: SwapTryAgainCoin(
                chainRawValue: Chain.ethereum.rawValue,
                ticker: "USDC",
                contractAddress: Self.curatedUSDC.lowercased(),
                address: nil
            ),
            to: SwapTryAgainCoin(coin: btc)
        )

        XCTAssertEqual(SwapTryAgain.pair(for: row, in: [usdc, btc])?.fromCoinID, usdc.id)
    }

    /// Where case is part of the address, a differently-cased contract is a
    /// different token.
    func testAContractIsMatchedExactlyWhereCaseIsPartOfTheAddress() {
        let jetton = makeCoin(chain: .ton, ticker: "USDT", contract: Self.tonJetton, address: "UQvault", native: false)
        let btc = makeBTC()
        let caseChangedRow = makeRow(
            from: SwapTryAgainCoin(
                chainRawValue: Chain.ton.rawValue,
                ticker: "USDT",
                contractAddress: Self.tonJetton.lowercased(),
                address: nil
            ),
            to: SwapTryAgainCoin(coin: btc)
        )

        XCTAssertNil(SwapTryAgain.pair(for: caseChangedRow, in: [jetton, btc]))
        XCTAssertEqual(SwapTryAgain.pair(for: makeRow(from: jetton, to: btc), in: [jetton, btc])?.fromCoinID, jetton.id)
    }

    func testANativeSideMatchesOnChainAndTickerAlone() {
        let eth = makeETH()
        let usdc = makeUSDC()

        let pair = SwapTryAgain.pair(for: makeRow(from: eth, to: usdc), in: [eth, usdc])

        XCTAssertEqual(pair, SwapTryAgainPair(fromCoinID: eth.id, toCoinID: usdc.id))
    }

    // MARK: - Legacy rows

    /// A row recorded before coin identity was stored still names its pair
    /// when the match is unambiguous: the source by chain and ticker, the
    /// destination by ticker and the address it paid out to.
    func testALegacyRowResolvesWhenTheMatchIsUnique() {
        let usdc = makeUSDC()
        let btc = makeBTC()

        let row = makeLegacyRow(fromTicker: "USDC", toTicker: "BTC", toAddress: btc.address)

        let pair = SwapTryAgain.pair(for: row, in: [makeETH(), usdc, btc])

        XCTAssertEqual(pair, SwapTryAgainPair(fromCoinID: usdc.id, toCoinID: btc.id))
    }

    func testALegacyRowThatFitsTwoSameTickerSourcesOffersNothing() {
        let curated = makeUSDC(contract: Self.curatedUSDC)
        let custom = makeUSDC(contract: Self.customUSDC)
        let btc = makeBTC()

        let row = makeLegacyRow(fromTicker: "USDC", toTicker: "BTC", toAddress: btc.address)

        XCTAssertNil(SwapTryAgain.pair(for: row, in: [curated, custom, btc]))
    }

    /// A legacy destination has no chain, and one EVM address holds the same
    /// ticker on every EVM chain — so it is ambiguous, and hidden.
    func testALegacyRowWhoseDestinationFitsTwoChainsOffersNothing() {
        let btc = makeBTC()
        let ethereumUSDC = makeUSDC()
        let arbitrumUSDC = makeUSDC(chain: .arbitrum)
        let row = makeLegacyRow(
            fromChain: .bitcoin,
            fromTicker: "BTC",
            toTicker: "USDC",
            toAddress: Self.evmAddress
        )

        XCTAssertNil(SwapTryAgain.pair(for: row, in: [btc, ethereumUSDC, arbitrumUSDC]))
        XCTAssertEqual(SwapTryAgain.pair(for: row, in: [btc, ethereumUSDC])?.toCoinID, ethereumUSDC.id)
    }

    // MARK: - When it is offered

    /// The done screen's single entry point: a pair only once the swap has
    /// failed, never while it may still land, and never for a limit order.
    func testTheOverviewOffersTryAgainOnlyOnAFailure() {
        let usdc = makeUSDC()
        let btc = makeBTC()
        let coins = [usdc, btc]
        func overviewPair(_ status: TransactionStatus, isLimitOrder: Bool = false) -> SwapTryAgainPair? {
            SwapTryAgain.pair(status: status, fromCoin: usdc, toCoin: btc, isLimitOrder: isLimitOrder, in: coins)
        }

        XCTAssertEqual(overviewPair(.failed(reason: "reverted")), SwapTryAgainPair(fromCoinID: usdc.id, toCoinID: btc.id))

        XCTAssertNil(overviewPair(.broadcasted(estimatedTime: "1m")))
        XCTAssertNil(overviewPair(.pending))
        XCTAssertNil(overviewPair(.confirmed))
        XCTAssertNil(overviewPair(.timeout))
        XCTAssertNil(overviewPair(.failed(reason: "reverted"), isLimitOrder: true))
    }

    func testHistoryOffersTryAgainOnlyOnAFailedSwapRow() {
        let usdc = makeUSDC()
        let btc = makeBTC()

        XCTAssertTrue(SwapTryAgain.isOffered(for: makeRow(from: usdc, to: btc, status: .error)))

        XCTAssertFalse(SwapTryAgain.isOffered(for: makeRow(from: usdc, to: btc, status: .inProgress)))
        XCTAssertFalse(SwapTryAgain.isOffered(for: makeRow(from: usdc, to: btc, status: .successful)))
        XCTAssertFalse(SwapTryAgain.isOffered(for: makeRow(from: usdc, to: btc, type: .limit, status: .error)))
        XCTAssertFalse(SwapTryAgain.isOffered(for: makeRow(from: usdc, to: btc, type: .send, status: .error)))
    }

    // MARK: - Fixtures

    private func makeCoin(chain: Chain, ticker: String, contract: String, address: String, native: Bool) -> Coin {
        Coin(
            asset: CoinMeta(
                chain: chain,
                ticker: ticker,
                logo: ticker.lowercased(),
                decimals: 6,
                priceProviderId: "",
                contractAddress: contract,
                isNativeToken: native
            ),
            address: address,
            hexPublicKey: ""
        )
    }

    private func makeETH() -> Coin {
        makeCoin(chain: .ethereum, ticker: "ETH", contract: "", address: Self.evmAddress, native: true)
    }

    private func makeUSDC(chain: Chain = .ethereum, contract: String = SwapTryAgainTests.curatedUSDC) -> Coin {
        makeCoin(chain: chain, ticker: "USDC", contract: contract, address: Self.evmAddress, native: false)
    }

    private func makeBTC() -> Coin {
        makeCoin(chain: .bitcoin, ticker: "BTC", contract: "", address: "bc1qvaultaddress", native: true)
    }

    private func makeRow(
        from: Coin,
        to: Coin,
        type: TransactionHistoryType = .swap,
        status: TransactionHistoryStatus = .error
    ) -> TransactionHistoryData {
        makeRow(from: SwapTryAgainCoin(coin: from), to: SwapTryAgainCoin(coin: to), type: type, status: status)
    }

    private func makeRow(
        from: SwapTryAgainCoin,
        to: SwapTryAgainCoin,
        type: TransactionHistoryType = .swap,
        status: TransactionHistoryStatus = .error
    ) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: "0xswap",
            approveTxHash: nil,
            pubKeyECDSA: "vault-pub",
            type: type,
            status: status,
            chainRawValue: from.chainRawValue ?? "",
            coinTicker: from.ticker,
            coinLogo: "",
            coinChainLogo: nil,
            amountCrypto: "1",
            amountFiat: "1",
            fromAddress: from.address ?? "",
            toAddress: to.address ?? "",
            toCoinTicker: to.ticker,
            toCoinLogo: nil,
            toCoinChainLogo: nil,
            toAmountCrypto: "1",
            toAmountFiat: "1",
            swapProvider: "THORChain",
            fromContractAddress: from.contractAddress,
            toChainRawValue: to.chainRawValue,
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

    private func makeLegacyRow(
        fromChain: Chain = .ethereum,
        fromTicker: String,
        toTicker: String,
        toAddress: String
    ) -> TransactionHistoryData {
        TransactionHistoryData(
            id: UUID(),
            txHash: "0xlegacy",
            approveTxHash: nil,
            pubKeyECDSA: "vault-pub",
            type: .swap,
            status: .error,
            chainRawValue: fromChain.rawValue,
            coinTicker: fromTicker,
            coinLogo: "",
            coinChainLogo: nil,
            amountCrypto: "1",
            amountFiat: "1",
            fromAddress: "",
            toAddress: toAddress,
            toCoinTicker: toTicker,
            toCoinLogo: nil,
            toCoinChainLogo: nil,
            toAmountCrypto: "1",
            toAmountFiat: "1",
            swapProvider: "THORChain",
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
