//
//  JoinKeysignAmountFiatTests.swift
//  VultisigAppTests
//
//  Pins `JoinKeysignViewModel.getAmountFiat()` — the co-sign "Send overview"
//  amount fiat that renders under the send amount, consistent with the network
//  fee. Display-only: `getAmountFiat` derives from the already-signed
//  `toAmount` + the shared `RateProvider` price and never affects signing
//  bytes. The helper must produce a fiat string only for a plain, priced coin
//  send and stay empty for swaps, contract-call/approval decodes, zero-value
//  sends, and coins without a rate — so nothing misleading renders.
//

@testable import VultisigApp
import BigInt
import XCTest

@MainActor
final class JoinKeysignAmountFiatTests: XCTestCase {

    func testAmountFiatUsesCoinPriceAndAmount() {
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: coin)
        // 3 ETH at $2 = $6.
        let vm = makeViewModel(payload: makePayload(coin: coin, toAmount: BigInt("3000000000000000000")))

        let fiat = vm.getAmountFiat()
        XCTAssertFalse(fiat.isEmpty, "A seeded rate should produce a fiat string")
        XCTAssertTrue(fiat.contains("6"), "3 ETH at $2 should render as 6, got \(fiat)")
    }

    func testAmountFiatScalesWithAmount() {
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: coin)
        // 5 ETH at $2 = $10.
        let vm = makeViewModel(payload: makePayload(coin: coin, toAmount: BigInt("5000000000000000000")))

        let fiat = vm.getAmountFiat()
        XCTAssertTrue(fiat.contains("10"), "5 ETH at $2 should render as 10, got \(fiat)")
    }

    func testAmountFiatEmptyWithoutRate() {
        // Unique ticker → unique priceProviderId that nothing seeds a rate for.
        let coin = makeCoin(.ethereum, ticker: "NORATEZZ", decimals: 18, isNative: true)
        let vm = makeViewModel(payload: makePayload(coin: coin, toAmount: BigInt("1000000000000000000")))
        XCTAssertEqual(vm.getAmountFiat(), "", "No rate → empty, never a misleading $0.00")
    }

    func testAmountFiatEmptyForZeroAmount() {
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: coin)
        let vm = makeViewModel(payload: makePayload(coin: coin, toAmount: 0))
        XCTAssertEqual(vm.getAmountFiat(), "", "A zero-value send maps to no meaningful fiat")
    }

    func testAmountFiatEmptyForContractCallTokenDisplay() {
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: coin)
        let vm = makeViewModel(payload: makePayload(coin: coin, toAmount: BigInt("3000000000000000000")))
        // A resolved contract-call / approval token display means the amount row
        // shows a decoded token, not the native coin transfer.
        vm.decodedTokenDisplay = "0.3 USDC"
        XCTAssertEqual(vm.getAmountFiat(), "", "Contract-call decodes carry their own display, not amount fiat")
    }

    func testAmountFiatEmptyForSwap() {
        let from = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        setPrice(2.0, for: from)
        let swap = SwapPayload.generic(makeGenericSwapPayload(from: from))
        let vm = makeViewModel(payload: makePayload(
            coin: from,
            toAmount: BigInt("3000000000000000000"),
            swapPayload: swap
        ))
        XCTAssertEqual(vm.getAmountFiat(), "", "Swaps show fiat on the hero from/to rows, not the amount field")
    }

    func testCosignerReviewClassifiesSwapAndLiquidityBySignedMemo() {
        let from = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let swap = SwapPayload.generic(makeGenericSwapPayload(from: from))
        let swapPayload = makePayload(coin: from, toAmount: 1, swapPayload: swap)
        XCTAssertEqual(JoinKeysignReviewPresentation.kind(for: swapPayload), .swap)

        let liquidityPayload = makePayload(coin: from, toAmount: 1, swapPayload: swap, memo: "+:ETH.ETH:0xpaired")
        XCTAssertEqual(JoinKeysignReviewPresentation.kind(for: liquidityPayload), .function)
    }

    func testCosignerReviewClassifiesSignedStakeAndWithdrawAsFunction() {
        let tcy = makeCoin(.thorChain, ticker: "TCY", decimals: 8, isNative: false)
        let specific = BlockChainSpecific.THORChain(accountNumber: 0, sequence: 0, fee: 0, isDeposit: true)
        let stake = makePayload(coin: tcy, toAmount: 100_000_000, memo: "tcy+", chainSpecific: specific)
        let withdraw = makePayload(coin: tcy, toAmount: 0, memo: "tcy-:5006", chainSpecific: specific)

        XCTAssertEqual(JoinKeysignReviewPresentation.kind(for: stake), .function)
        XCTAssertEqual(JoinKeysignReviewPresentation.kind(for: withdraw), .function)
        let stakeSummary = JoinKeysignReviewPresentation.functionSummary(viewModel: makeViewModel(payload: stake))
        XCTAssertFalse(stakeSummary?.rows.contains(where: { $0.label == "to".localized }) ?? true)
    }

    func testCosignerSwapSummaryUsesReceivedAmountsAndRecipient() {
        let from = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let swap = SwapPayload.generic(makeGenericSwapPayload(from: from))
        let vm = makeViewModel(payload: makePayload(coin: from, toAmount: 1, swapPayload: swap))
        let summary = JoinKeysignReviewPresentation.swapSummary(viewModel: vm)

        XCTAssertEqual(summary?.from.amount, "3")
        XCTAssertEqual(summary?.to.amount, Decimal(3000).formatForDisplay())
        XCTAssertEqual(summary?.from.ticker, "ETH")
        XCTAssertEqual(summary?.to.ticker, "USDC")
    }

    func testCosignerSwapFeeRowsUseInitiatorLabelsAndParenthesizedFiat() {
        let from = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let feeCoin = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, contract: "0xusdc")
        setPrice(2.0, for: from)
        setPrice(1.0, for: feeCoin)
        let vm = makeViewModel(payload: makePayload(
            coin: from,
            toAmount: 1,
            swapPayload: .generic(makeGenericSwapPayload(from: from, swapFee: "1000000"))
        ))
        let networkFee = vm.getCalculatedNetworkFee()
        let summary = JoinKeysignReviewPresentation.swapSummary(viewModel: vm)

        XCTAssertEqual(summary?.feeLines.first?.label, "networkFee".localized)
        XCTAssertEqual(
            summary?.feeLines.first?.value,
            "\(networkFee.feeCrypto) (\(networkFee.feeFiat))"
        )
        XCTAssertEqual(summary?.feeLines.dropFirst().first?.label, "vultisigFee".localized)
        XCTAssertEqual(summary?.feeLines.dropFirst().first?.value, "1 USDC (\(Decimal(1).formatToFiatForFee(includeCurrencySymbol: true)))")
        XCTAssertEqual(summary?.totalFee, Decimal(1).formatToFiat(includeCurrencySymbol: true))
        XCTAssertNil(summary?.slippage, "Quote-only slippage must not be invented from a received payload")
    }

    func testCosignerLiquidityUsesFunctionOverviewSummary() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let swap = SwapPayload.generic(makeGenericSwapPayload(from: eth))
        let vm = makeViewModel(payload: makePayload(
            coin: eth, toAmount: 1, swapPayload: swap, memo: "+:ETH.ETH:0xpaired"
        ))

        let summary = JoinKeysignReviewPresentation.functionSummary(viewModel: vm)
        let sharedContent = JoinKeysignReviewPresentation.summary(for: .function, viewModel: vm)

        XCTAssertEqual(summary?.vaultAddress, eth.address)
        XCTAssertEqual(summary?.rows.first?.label, "to".localized)
        XCTAssertEqual(summary?.rows.first?.value, "0xrecipient")
        guard case .function = sharedContent else {
            return XCTFail("Liquidity must use the shared function overview renderer")
        }
    }

    func testCosignerSendSummaryUsesReceivedDestination() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let vm = makeViewModel(payload: makePayload(coin: eth, toAmount: BigInt("1000000000000000000")))
        let summary = JoinKeysignReviewPresentation.sendSummary(viewModel: vm)

        XCTAssertEqual(summary.fromAddress, eth.address)
        XCTAssertEqual(summary.toAddress, "0xrecipient")
        XCTAssertEqual(summary.amount, "1")
        XCTAssertEqual(summary.coinTicker, "ETH")
    }

    func testCosignerSheetOnlyPresentsForTransactionJoinStatus() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let payload = makePayload(coin: eth, toAmount: 1)

        XCTAssertEqual(JoinKeysignReviewPresentation.presentedKind(
            status: .JoinKeysign, payload: payload, hasCustomMessage: false
        ), .send)
        XCTAssertNil(JoinKeysignReviewPresentation.presentedKind(
            status: .WaitingForKeysignToStart, payload: payload, hasCustomMessage: false
        ))
        XCTAssertNil(JoinKeysignReviewPresentation.presentedKind(
            status: .JoinKeysign, payload: nil, hasCustomMessage: true
        ))
    }

    func testTransactionReviewReplacesSessionContentUntilSigningStarts() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let payload = makePayload(coin: eth, toAmount: 1)

        XCTAssertEqual(JoinKeysignReviewPresentation.surface(
            status: .JoinKeysign, payload: payload, hasCustomMessage: false
        ), .transactionReview(.send))
        XCTAssertEqual(JoinKeysignReviewPresentation.surface(
            status: .WaitingForKeysignToStart, payload: payload, hasCustomMessage: false
        ), .session)
        XCTAssertEqual(JoinKeysignReviewPresentation.surface(
            status: .KeysignStarted, payload: payload, hasCustomMessage: false
        ), .session)
        XCTAssertEqual(JoinKeysignReviewPresentation.surface(
            status: .JoinKeysign, payload: nil, hasCustomMessage: true
        ), .session)
        XCTAssertEqual(JoinKeysignReviewPresentation.surface(
            status: .QBTCClaim, payload: payload, hasCustomMessage: false
        ), .session)
    }

    func testRepeatedJoinStatusDoesNotResetOrReopenReview() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let payload = makePayload(coin: eth, toAmount: 1)

        XCTAssertEqual(JoinKeysignReviewPresentation.newReviewKind(
            status: .JoinKeysign, payload: payload, hasCustomMessage: false, wasReviewStatus: false
        ), .send)
        XCTAssertNil(JoinKeysignReviewPresentation.newReviewKind(
            status: .JoinKeysign, payload: payload, hasCustomMessage: false, wasReviewStatus: true
        ))
        XCTAssertNil(JoinKeysignReviewPresentation.newReviewKind(
            status: .WaitingForKeysignToStart, payload: payload, hasCustomMessage: false, wasReviewStatus: true
        ))
    }

    func testScannerKeysignHandoffWaitsForDismissal() {
        var handoff = ScannerKeysignHandoff()

        XCTAssertTrue(handoff.requestJoin(), "A direct link needs no scanner dismissal")
        XCTAssertTrue(handoff.reviewReady(), "A prepared direct link can present immediately")
        handoff.scannerOpened()
        XCTAssertFalse(handoff.requestJoin(), "A scanned QR must defer the overview")
        XCTAssertFalse(handoff.scannerDismissed(isPresentingAgain: false), "Dismissal alone must not present an unprepared review")
        XCTAssertTrue(handoff.reviewReady(), "A review ready after dismissal can present immediately")
        XCTAssertFalse(handoff.scannerDismissed(isPresentingAgain: false), "The dismissal must hand off only once")
    }

    func testScannerKeysignHandoffWaitsForDismissalAfterReviewIsReady() {
        var handoff = ScannerKeysignHandoff()

        handoff.scannerOpened()
        XCTAssertFalse(handoff.requestJoin())
        XCTAssertFalse(handoff.reviewReady(), "Readiness while scanning cannot present over the scanner")
        XCTAssertTrue(handoff.scannerDismissed(isPresentingAgain: false))
        XCTAssertFalse(handoff.reviewReady(), "A repeated ready event cannot reopen a dismissed review")
    }

    func testScannerKeysignHandoffIgnoresCancellationAndReopen() {
        var handoff = ScannerKeysignHandoff()

        handoff.scannerOpened()
        XCTAssertFalse(handoff.scannerDismissed(isPresentingAgain: false), "Cancelling cannot open the overview")

        handoff.scannerOpened()
        XCTAssertFalse(handoff.requestJoin())
        XCTAssertFalse(handoff.reviewReady())
        handoff.scannerOpened()
        XCTAssertFalse(handoff.scannerDismissed(isPresentingAgain: true), "An old dismissal cannot close a new scan")
        XCTAssertFalse(handoff.scannerDismissed(isPresentingAgain: false), "Reopening cancels the old QR handoff")
    }

    func testCosignerScanResetsToLoadingWhenReviewReopens() {
        let vm = JoinKeysignViewModel()
        vm.securityScannerState = .scanned(KeysignReviewScanFixture.result(.high))
        vm.didLoadSimulation = true

        vm.resetReviewScan()

        XCTAssertEqual(KeysignReviewScanRing(vm.securityScannerState, isScanComplete: vm.didLoadSimulation).animationState, .loading)
        XCTAssertFalse(vm.didLoadSimulation)
    }

    func testCosignerRiskVerdictOnlyRequiresAcknowledgementForUnsafeResult() {
        XCTAssertTrue(JoinKeysignReviewPresentation.requiresRiskAcknowledgement(
            .scanned(KeysignReviewScanFixture.result(.medium))
        ))
        XCTAssertTrue(JoinKeysignReviewPresentation.requiresRiskAcknowledgement(
            .scanned(KeysignReviewScanFixture.result(.high))
        ))
        XCTAssertFalse(JoinKeysignReviewPresentation.requiresRiskAcknowledgement(
            .scanned(KeysignReviewScanFixture.result(.low))
        ))
        XCTAssertFalse(JoinKeysignReviewPresentation.requiresRiskAcknowledgement(.idle))
        XCTAssertFalse(JoinKeysignReviewPresentation.requiresRiskAcknowledgement(.notScanned(provider: "blockaid")))
    }

    func testUnavailableCosignerScanCompletesAndHidesAnimation() {
        let vm = JoinKeysignViewModel()
        vm.securityScannerState = .scanning

        vm.finishReviewScan(scannerResult: nil)

        XCTAssertTrue(vm.didLoadSimulation)
        XCTAssertEqual(KeysignReviewScanRing(vm.securityScannerState, isScanComplete: vm.didLoadSimulation), .hidden)
    }

    // MARK: - Co-signer keysign hero (JoinKeysignViewModel.heroContent)

    /// The co-signer builds its hero through the same
    /// `BlockaidSimulationInfo.heroContent(title:vaultCoins:)` the initiator
    /// uses, but reaches it past an extra TON fallback branch. Pinned on both
    /// devices because a hero that named the wrong direction on one of them
    /// would still be the screen the approval decision rests on.
    func testCoSignerHeroReceiveMapsToReceiveHero() {
        let sol = makeCoin(.solana, ticker: "SOL", decimals: 9, isNative: true)
        setPrice(3.0, for: sol)
        let vm = makeViewModel(payload: makePayload(coin: sol, toAmount: .zero))
        vm.vault = makeVault(coins: [sol])
        // A wrapped-SOL withdraw nets to an inflow of 2 SOL. At $3 = $6.
        vm.blockaidSimulation = .receive(
            coin: BlockaidSimulationCoin(
                chain: .solana,
                address: BlockaidSimulationParser.wrappedSolMint,
                ticker: "SOL",
                logo: "logo",
                decimals: 9
            ),
            amount: BigInt("2000000000")
        )

        guard case .receive(_, let coin) = vm.heroContent else {
            return XCTFail("A receive simulation must produce a receive hero, never a send")
        }
        XCTAssertEqual(coin.ticker, "SOL")
        XCTAssertTrue(coin.fiat?.contains("6") == true, "2 SOL at $3 should render as 6, got \(coin.fiat ?? "nil")")
    }

    // MARK: - Helpers

    private func makeVault(coins: [Coin]) -> Vault {
        let vault = Vault(name: "cosign-hero-test-vault")
        vault.coins = coins
        return vault
    }

    private func makeViewModel(payload: KeysignPayload) -> JoinKeysignViewModel {
        let vm = JoinKeysignViewModel()
        vm.keysignPayload = payload
        return vm
    }

    private func makePayload(
        coin: Coin,
        toAmount: BigInt,
        swapPayload: SwapPayload? = nil,
        memo: String? = nil,
        chainSpecific: BlockChainSpecific? = nil
    ) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: "0xrecipient",
            toAmount: toAmount,
            chainSpecific: chainSpecific ?? .Ethereum(maxFeePerGasWei: 0, priorityFeeWei: 0, nonce: 0, gasLimit: 21000),
            utxos: [],
            memo: memo,
            swapPayload: swapPayload,
            approvePayload: nil,
            vaultPubKeyECDSA: "",
            vaultLocalPartyID: "",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }

    private func makeGenericSwapPayload(from: Coin, swapFee: String? = nil) -> GenericSwapPayload {
        GenericSwapPayload(
            fromCoin: from,
            toCoin: makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, contract: "0xusdc"),
            fromAmount: BigInt("3000000000000000000"),
            toAmountDecimal: 3000,
            quote: EVMQuote(
                dstAmount: "3000000000",
                tx: EVMQuote.Transaction(
                    from: "0xFrom",
                    to: "0xRouter",
                    data: "0x",
                    value: "0",
                    gasPrice: "1",
                    gas: 100_000,
                    swapFee: swapFee
                )
            ),
            provider: .oneInch,
            swapFeeChain: swapFee == nil ? nil : Chain.ethereum.name,
            swapFeeTokenId: swapFee == nil ? nil : "0xusdc",
            swapFeeDecimals: swapFee == nil ? nil : 6
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, contract: String = "") -> Coin {
        let asset = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "logo",
            decimals: decimals,
            priceProviderId: ticker.lowercased(),
            contractAddress: contract,
            isNativeToken: isNative
        )
        return Coin(asset: asset, address: "test-\(ticker)", hexPublicKey: "")
    }

    private func setPrice(_ value: Double, for coin: Coin) {
        let cryptoId = RateProvider.cryptoId(for: coin.toCoinMeta()).id
        try? RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: cryptoId, value: value)
        ])
    }
}
