//
//  SwapAffiliateFeeDisplayTests.swift
//  VultisigAppTests
//
//  First real coverage for the affiliate-fee display helpers exercised by the
//  Verify / Details / Done screens (#4859): the shared effective-affiliate-bps
//  function, the bps-derived percentage label, per-route affiliate amounts, the
//  Total-fee reconciliation (which drops the fees.total liquidity component),
//  the row-visibility gate, and the display-only invariant that none of this
//  touches the signed keysign payload.
//
//  DEBUG note: `THORChainSwaps.affiliateFeeRateBp` is 0 in test builds, so
//  non-referred native percentages read 0.00% here — that matches what the
//  request builder sends in DEBUG. Base-50 tier math is asserted directly on
//  the pure `discountedAffiliateBps` helper so it's independent of the build.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapAffiliateFeeDisplayTests: XCTestCase {

    // MARK: - Shared effective-affiliate-bps (pure, build-independent)

    func testDiscountedAffiliateBpsBaseFiftyPerTier() {
        func bps(_ discount: Int) -> Int {
            THORChainSwaps.discountedAffiliateBps(baseBps: 50, discountBps: discount)
        }
        XCTAssertEqual(bps(0), 50)                                    // no tier
        XCTAssertEqual(bps(VultDiscountTier.bronze.bpsDiscount), 45)  // 5
        XCTAssertEqual(bps(VultDiscountTier.silver.bpsDiscount), 40)  // 10
        XCTAssertEqual(bps(VultDiscountTier.gold.bpsDiscount), 30)    // 20
        XCTAssertEqual(bps(VultDiscountTier.platinum.bpsDiscount), 25) // 25
        XCTAssertEqual(bps(VultDiscountTier.diamond.bpsDiscount), 15) // 35
        XCTAssertEqual(bps(VultDiscountTier.ultimate.bpsDiscount), 0) // Int.max → 0
    }

    func testDiscountedAffiliateBpsUltimateDoesNotOverflow() {
        // Int.max discount must clamp to 0, not trap on `50 - Int.max`.
        XCTAssertEqual(THORChainSwaps.discountedAffiliateBps(baseBps: 50, discountBps: .max), 0)
    }

    func testEffectiveAffiliateFeeBpsNonReferredMatchesDiscounted() {
        for discount in [0, 5, 10, 20, 25, 35, Int.max] {
            XCTAssertEqual(
                THORChainSwaps.effectiveAffiliateFeeBps(discountBps: discount, isReferred: false),
                THORChainSwaps.discountedAffiliateBps(baseBps: THORChainSwaps.affiliateFeeRateBp, discountBps: discount)
            )
        }
    }

    func testEffectiveAffiliateFeeBpsReferredAddsReferrerShare() {
        let referrer = Int(THORChainSwaps.referredUserFeeRateBp) ?? 0 // 10
        // Referred total = referrer share + discounted 35-bp Vultisig share.
        XCTAssertEqual(THORChainSwaps.effectiveAffiliateFeeBps(discountBps: 0, isReferred: true), referrer + 35)   // 45
        XCTAssertEqual(THORChainSwaps.effectiveAffiliateFeeBps(discountBps: 35, isReferred: true), referrer + 0)   // 10 (diamond)
        XCTAssertEqual(THORChainSwaps.effectiveAffiliateFeeBps(discountBps: .max, isReferred: true), referrer)     // 10 (ultimate keeps the referrer share)
    }

    // MARK: - Display bps equals the request builder's sent bps

    func testDisplayBpsMatchesThorchainRequestBuilderNonReferred() {
        for discount in [0, 5, 35] {
            let (_, bpsStr) = ThorchainService.affiliateParams(referredCode: "", discountBps: discount)
            let sent = Int(bpsStr ?? "") ?? -1
            XCTAssertEqual(sent, THORChainSwaps.effectiveAffiliateFeeBps(discountBps: discount, isReferred: false))
        }
    }

    func testDisplayBpsMatchesThorchainRequestBuilderReferred() {
        for discount in [0, 5, 35] {
            let (_, bpsStr) = ThorchainService.affiliateParams(referredCode: "code", discountBps: discount)
            // Referred builder sends "referrer/vultisig"; the total charged is the sum.
            let sentTotal = (bpsStr ?? "").split(separator: "/").compactMap { Int($0) }.reduce(0, +)
            XCTAssertEqual(sentTotal, THORChainSwaps.effectiveAffiliateFeeBps(discountBps: discount, isReferred: true))
        }
    }

    // MARK: - swapFeeLabel percentage per route

    func testSwapFeeLabelNativeThorchainDerivesFromBps() {
        let btc = makeCoin(.bitcoin, ticker: "BTCLBL", decimals: 8, isNative: true)
        let label = SwapCryptoLogic.swapFeeLabel(
            quote: .thorchain(makeThorQuote()), fromCoin: btc, toCoin: btc, feeCoin: btc,
            fromAmount: "1", vultDiscountBps: 0, isReferred: false
        )
        let expectedBps = THORChainSwaps.effectiveAffiliateFeeBps(discountBps: 0, isReferred: false)
        XCTAssertEqual(label, String(format: "vultisigFeePercentage".localized, Double(expectedBps) / 100.0))
    }

    func testSwapFeeLabelThorchainReferredShowsReferredSplit() {
        let btc = makeCoin(.bitcoin, ticker: "BTCREF", decimals: 8, isNative: true)
        let label = SwapCryptoLogic.swapFeeLabel(
            quote: .thorchain(makeThorQuote()), fromCoin: btc, toCoin: btc, feeCoin: btc,
            fromAmount: "1", vultDiscountBps: 0, isReferred: true
        )
        // 10 (referrer) + 35 (discounted base 35) = 45 bps, even in DEBUG.
        XCTAssertEqual(label, String(format: "vultisigFeePercentage".localized, 0.45))
    }

    func testSwapFeeLabelMayaIgnoresReferralSplit() {
        let btc = makeCoin(.bitcoin, ticker: "BTCMAYA", decimals: 8, isNative: true)
        let mayaReferred = SwapCryptoLogic.swapFeeLabel(
            quote: .mayachain(makeThorQuote()), fromCoin: btc, toCoin: btc, feeCoin: btc,
            fromAmount: "1", vultDiscountBps: 0, isReferred: true
        )
        let thorReferred = SwapCryptoLogic.swapFeeLabel(
            quote: .thorchain(makeThorQuote()), fromCoin: btc, toCoin: btc, feeCoin: btc,
            fromAmount: "1", vultDiscountBps: 0, isReferred: true
        )
        let thorNonReferred = SwapCryptoLogic.swapFeeLabel(
            quote: .thorchain(makeThorQuote()), fromCoin: btc, toCoin: btc, feeCoin: btc,
            fromAmount: "1", vultDiscountBps: 0, isReferred: false
        )
        // Maya never applies the referral split → it must match the standard
        // (non-referred) rate, not the THORChain referred rate.
        XCTAssertEqual(mayaReferred, thorNonReferred)
        XCTAssertNotEqual(mayaReferred, thorReferred)
    }

    func testSwapFeeLabelSwapKitStaticHalfPercent() {
        let btc = makeCoin(.bitcoin, ticker: "BTCSK", decimals: 8, isNative: true)
        let label = SwapCryptoLogic.swapFeeLabel(
            quote: makeSwapKitQuote(), fromCoin: btc, toCoin: btc, feeCoin: btc,
            fromAmount: "1", vultDiscountBps: 0, isReferred: false
        )
        XCTAssertEqual(label, String(format: "vultisigFeePercentage".localized, 0.50))
    }

    // MARK: - baseAffiliateFee amount per route

    func testBaseAffiliateFeeSourcesAffiliateNotComposite() {
        let btc = makeCoin(.bitcoin, ticker: "BTCAFF", decimals: 8, isNative: true)
        setPrice(1000, for: btc)
        // affiliate 0.01 BTC → $10; total (composite) 0.09 BTC would be $90.
        let quote = SwapQuote.thorchain(makeThorQuote(affiliate: "1000000", outbound: "0", total: "9000000"))
        let value = SwapCryptoLogic.baseAffiliateFee(quote: quote, fromCoin: btc, toCoin: btc, feeCoin: btc)
        XCTAssertEqual(value, Decimal(10).formatToFiat(includeCurrencySymbol: true))
        XCTAssertNotEqual(value, Decimal(90).formatToFiat(includeCurrencySymbol: true))
    }

    func testBaseAffiliateFeeUltimateShowsZeroNotEmpty() {
        let btc = makeCoin(.bitcoin, ticker: "BTCULT", decimals: 8, isNative: true)
        setPrice(1000, for: btc)
        // Ultimate/100% waiver → node charges 0 affiliate; the row stays at $0.00.
        let quote = SwapQuote.thorchain(makeThorQuote(affiliate: "0", outbound: "0", total: "0"))
        let value = SwapCryptoLogic.baseAffiliateFee(quote: quote, fromCoin: btc, toCoin: btc, feeCoin: btc)
        XCTAssertFalse(value.isEmpty)
        XCTAssertEqual(value, Decimal(0).formatToFiat(includeCurrencySymbol: true))
    }

    func testBaseAffiliateFeeSwapKitIncludedInRate() {
        let btc = makeCoin(.bitcoin, ticker: "BTCSK2", decimals: 8, isNative: true)
        let value = SwapCryptoLogic.baseAffiliateFee(quote: makeSwapKitQuote(), fromCoin: btc, toCoin: btc, feeCoin: btc)
        XCTAssertEqual(value, "swap.included_in_rate".localized)
    }

    func testBaseAffiliateFeeJupiterUsesPlatformFee() {
        let sol = makeCoin(.solana, ticker: "SOLJUP", decimals: 9, isNative: true)
        let usdc = makeCoin(.solana, ticker: "USDCJUP", decimals: 6, isNative: false)
        setPrice(2, for: usdc) // 1 USDC = $2 for the test
        // platformFee 0.02 USDC × $2 = $0.04 (hardcoded so a silent rate-seeding
        // failure would fail the test rather than pass at $0.00 on both sides).
        let quote = makeJupiterQuote(platformFee: Decimal(2) / Decimal(100), feeOnInput: false)
        let value = SwapCryptoLogic.baseAffiliateFee(quote: quote, fromCoin: sol, toCoin: usdc, feeCoin: sol)
        XCTAssertEqual(value, (Decimal(4) / Decimal(100)).formatToFiat(includeCurrencySymbol: true))
    }

    // MARK: - Row visibility gate

    func testShowAffiliateFeeRowTrueForMarketSwap() {
        XCTAssertTrue(SwapCryptoLogic.showAffiliateFeeRow(quote: .thorchain(makeThorQuote()), mode: .standard))
    }

    func testShowAffiliateFeeRowFalseForSecuredMint() {
        XCTAssertFalse(SwapCryptoLogic.showAffiliateFeeRow(quote: .thorchain(makeThorQuote()), mode: .securedMint))
    }

    func testShowAffiliateFeeRowFalseForNilQuote() {
        XCTAssertFalse(SwapCryptoLogic.showAffiliateFeeRow(quote: nil, mode: .standard))
    }

    func testShowAffiliateFeeRowFalseForNativeSolJupiter() {
        // feeOnInput ⇒ fee taken on the input mint (native-SOL output); the
        // amount isn't surfaced in toCoin units, so suppress rather than show a
        // misleading $0.00.
        XCTAssertFalse(SwapCryptoLogic.showAffiliateFeeRow(quote: makeJupiterQuote(platformFee: 0, feeOnInput: true), mode: .standard))
    }

    func testShowAffiliateFeeRowTrueForTokenJupiter() {
        let quote = makeJupiterQuote(platformFee: Decimal(string: "0.01") ?? 0, feeOnInput: false)
        XCTAssertTrue(SwapCryptoLogic.showAffiliateFeeRow(quote: quote, mode: .standard))
    }

    func testShowAffiliateFeeRowTrueForUltimateTokenJupiter() {
        // Ultimate tier, token output: the fee is on the OUTPUT mint but zero.
        // The row must still show (0.00% / $0.00), NOT be suppressed like the
        // input-mint (native-SOL) case.
        XCTAssertTrue(SwapCryptoLogic.showAffiliateFeeRow(quote: makeJupiterQuote(platformFee: 0, feeOnInput: false), mode: .standard))
    }

    func testBaseAffiliateFeeUltimateTokenJupiterShowsZero() {
        let sol = makeCoin(.solana, ticker: "SOLJUP0", decimals: 9, isNative: true)
        let usdc = makeCoin(.solana, ticker: "USDCJUP0", decimals: 6, isNative: false)
        setPrice(2, for: usdc)
        let value = SwapCryptoLogic.baseAffiliateFee(
            quote: makeJupiterQuote(platformFee: 0, feeOnInput: false), fromCoin: sol, toCoin: usdc, feeCoin: sol
        )
        XCTAssertEqual(value, Decimal(0).formatToFiat(includeCurrencySymbol: true))
    }

    func testAffiliateFeeFiatLifiSolanaUsesIntegratorFee() {
        let sol = makeCoin(.solana, ticker: "SOLLIFI", decimals: 9, isNative: true)
        let usdc = makeCoin(.solana, ticker: "USDCLIFI", decimals: 6, isNative: false)
        setPrice(1, for: usdc) // 1 USDC = $1
        // LiFi-Solana: swapFee "0"; integrator fee 0.005 of the 100-USDC output
        // (dstAmount 100_000_000 at 6 dp) → 0.5 USDC → $0.50. Must appear in the
        // row and the Total (network 0 + affiliate 0.5 + outbound 0).
        let quote = makeLiFiSolanaQuote(integratorFee: Decimal(5) / Decimal(1000), dstAmount: "100000000")
        let expected = (Decimal(5) / Decimal(10)).formatToFiat(includeCurrencySymbol: true)
        XCTAssertEqual(SwapCryptoLogic.baseAffiliateFee(quote: quote, fromCoin: sol, toCoin: usdc, feeCoin: sol), expected)
        XCTAssertEqual(
            SwapCryptoLogic.totalFeeString(quote: quote, fromCoin: sol, toCoin: usdc, feeCoin: sol, fee: .zero),
            expected
        )
        // NOT $0.00 — the old evmSwapFeeBigInt-only path dropped the integrator fee.
        XCTAssertNotEqual(SwapCryptoLogic.baseAffiliateFee(quote: quote, fromCoin: sol, toCoin: usdc, feeCoin: sol),
                          Decimal(0).formatToFiat(includeCurrencySymbol: true))
    }

    func testShowProtocolFeeRowFalseForSecuredMint() {
        let btc = makeCoin(.bitcoin, ticker: "BTCPROT", decimals: 8, isNative: true)
        // Secured mint's synthetic quote reports a zero outbound that is not a
        // real protocol fee, so the row must be suppressed (no spurious $0.00).
        let quote = SwapQuote.thorchain(makeThorQuote(outbound: "0"))
        XCTAssertFalse(SwapCryptoLogic.showProtocolFeeRow(quote: quote, toCoin: btc, mode: .securedMint))
    }

    func testShowProtocolFeeRowTrueForNativeSwap() {
        let btc = makeCoin(.bitcoin, ticker: "BTCPROT2", decimals: 8, isNative: true)
        let quote = SwapQuote.thorchain(makeThorQuote(outbound: "2000000"))
        XCTAssertTrue(SwapCryptoLogic.showProtocolFeeRow(quote: quote, toCoin: btc, mode: .standard))
    }

    func testShowProtocolFeeRowFalseForNonNativeRoute() {
        let usdc = makeCoin(.solana, ticker: "USDCPR", decimals: 6, isNative: false)
        // Jupiter / EVM aggregators have no native protocol outbound fee.
        let quote = makeJupiterQuote(platformFee: Decimal(string: "0.01") ?? 0, feeOnInput: false)
        XCTAssertFalse(SwapCryptoLogic.showProtocolFeeRow(quote: quote, toCoin: usdc, mode: .standard))
    }

    // MARK: - Total-fee reconciliation (Network + affiliate + outbound, no liquidity)

    func testTotalFeeReconcilesAndDropsLiquidity() {
        let rune = makeCoin(.thorChain, ticker: "RUNETOT", decimals: 8, isNative: true)
        let btc = makeCoin(.bitcoin, ticker: "BTCTOT", decimals: 8, isNative: true)
        setPrice(10, for: rune)   // network fee coin
        setPrice(1000, for: btc)  // output coin (affiliate + outbound denominated here)

        // affiliate 0.01 BTC = $10, outbound 0.02 BTC = $20, total(composite)
        // 0.09 BTC = $90 (carries $60 of liquidity that must be dropped).
        let quote = SwapQuote.thorchain(makeThorQuote(affiliate: "1000000", outbound: "2000000", total: "9000000"))
        let networkFeeWei = BigInt(100_000_000) // 1 RUNE = $10

        let total = SwapCryptoLogic.totalFeeString(quote: quote, fromCoin: rune, toCoin: btc, feeCoin: rune, fee: networkFeeWei)

        // Reconciled: $10 network + $10 affiliate + $20 outbound = $40 (computed
        // by hand from the inputs, independent of the helper's own arithmetic).
        XCTAssertEqual(total, Decimal(40).formatToFiat(includeCurrencySymbol: true))
        // NOT the old composite path ($10 network + $90 fees.total = $100).
        XCTAssertNotEqual(total, Decimal(100).formatToFiat(includeCurrencySymbol: true))
    }

    // MARK: - Display-only invariant: signed payload unchanged

    func testDisplayFeeInputsDoNotAlterSignedPayload() async throws {
        let vault = makeVault()
        let quote = makeThorQuote(affiliate: "1000000", outbound: "2000000", total: "9000000", memo: "=:BTC.BTC:addr:0/1/0")

        // Baseline (no tier, no referral) vs. a heavily-discounted referred user:
        // only the DISPLAY fee inputs differ — the signed artifact must not.
        let baseline = makeNativeThorchainTransaction(quote: quote, vultDiscountBps: 0, referralDiscountBps: 0, isReferred: false)
        let discounted = makeNativeThorchainTransaction(quote: quote, vultDiscountBps: 35, referralDiscountBps: 5, isReferred: true)

        let p1 = try await SwapCryptoLogic.buildSwapKeysignPayload(transaction: baseline, chainSpecific: cosmosChainSpecific(), vault: vault)
        let p2 = try await SwapCryptoLogic.buildSwapKeysignPayload(transaction: discounted, chainSpecific: cosmosChainSpecific(), vault: vault)

        XCTAssertEqual(p1.memo, p2.memo, "Signed memo must not depend on display-fee inputs")
        XCTAssertEqual(p1.toAmount, p2.toAmount, "Signed amount must not depend on display-fee inputs")
        XCTAssertEqual(p1.toAddress, p2.toAddress)
        XCTAssertEqual(p1.memo, "=:BTC.BTC:addr:0/1/0")
    }

    // MARK: - Fixtures

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta(
            chain: chain, ticker: ticker, logo: "logo", decimals: decimals,
            priceProviderId: ticker.lowercased(), contractAddress: "", isNativeToken: isNative
        )
        return Coin(asset: asset, address: "test-\(ticker)", hexPublicKey: "")
    }

    private func setPrice(_ value: Double, for coin: Coin) {
        let cryptoId = RateProvider.cryptoId(for: coin.toCoinMeta()).id
        do {
            try RateProvider.shared.save(rates: [
                Rate(fiat: SettingsCurrency.current.rawValue, crypto: cryptoId, value: value)
            ])
        } catch {
            XCTFail("Failed to seed rate for \(coin.ticker): \(error)")
        }
        // Guard against a silent seeding failure making fiat assertions vacuous.
        XCTAssertEqual(coin.price, value, accuracy: 0.0001, "Rate for \(coin.ticker) did not take effect")
    }

    private func makeThorQuote(
        affiliate: String = "0",
        outbound: String = "0",
        total: String = "0",
        expectedAmountOut: String = "100000000",
        memo: String = "thor-memo",
        slippageBps: Int? = nil,
        router: String? = nil
    ) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: expectedAmountOut,
            expiry: 0,
            fees: Fees(affiliate: affiliate, asset: "RUNE", outbound: outbound, total: total, liquidity: nil, slippageBps: nil, totalBps: nil),
            inboundAddress: "thor-vault",
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: memo,
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            slippageBps: slippageBps,
            totalSwapSeconds: nil,
            warning: "",
            router: router,
            maxStreamingQuantity: nil
        )
    }

    private func makeJupiterQuote(platformFee: Decimal, feeOnInput: Bool) -> SwapQuote {
        let evm = EVMQuote(
            dstAmount: "1000000",
            tx: EVMQuote.Transaction(from: "from", to: "mint", data: "data", value: "0", gasPrice: "0", gas: 0)
        )
        return .jupiter(evm, fee: nil, platformFee: platformFee, feeOnInput: feeOnInput)
    }

    /// LiFi-Solana quote fixture: `swapFee` is "0" and the affiliate fee is
    /// carried as `integratorFee` (a fraction of the output amount), mirroring
    /// `LiFiService`'s Solana branch.
    private func makeLiFiSolanaQuote(integratorFee: Decimal, dstAmount: String) -> SwapQuote {
        let evm = EVMQuote(
            dstAmount: dstAmount,
            tx: EVMQuote.Transaction(
                from: "from", to: "to", data: "0x", value: "0", gasPrice: "0", gas: 0,
                swapFee: "0", swapFeeTokenContract: ""
            )
        )
        return .lifi(evm, fee: nil, integratorFee: integratorFee)
    }

    private func makeSwapKitQuote() -> SwapQuote {
        let json = """
        {
          "swapId": "s", "routeId": "r", "providers": ["Chainflip"],
          "sellAsset": "BTC.BTC", "buyAsset": "ETH.ETH", "sellAmount": "0.01",
          "expectedBuyAmount": "0.1", "expectedBuyAmountMaxSlippage": "0.1",
          "sourceAddress": "from", "destinationAddress": "to", "targetAddress": "target",
          "meta": { "txType": "EVM" },
          "tx": { "from": "from", "to": "to", "value": "0", "data": "0x", "gas": "0x30d40", "gasPrice": "0x4a817c800" },
          "fees": []
        }
        """
        // swiftlint:disable:next force_try
        let response = try! JSONDecoder().decode(SwapKitSwapResponse.self, from: Data(json.utf8))
        return .swapkit(response, fee: BigInt(10), subProvider: "Chainflip")
    }

    private func makeNativeThorchainTransaction(
        quote: ThorchainSwapQuote,
        vultDiscountBps: Int,
        referralDiscountBps: Int,
        isReferred: Bool
    ) -> SwapTransaction {
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        return SwapTransaction(
            fromCoin: rune,
            toCoin: btc,
            fromAmount: 1.0,
            kind: .market(.thorchain(quote)),
            gas: 0,
            gasLimit: 0,
            thorchainFee: BigInt(2_000),
            vultDiscountBps: vultDiscountBps,
            referralDiscountBps: referralDiscountBps,
            isReferred: isReferred,
            feeCoin: rune,
            advancedSettings: .default
        )
    }

    private func makeVault() -> Vault {
        Vault(
            name: "Test Vault",
            signers: [],
            pubKeyECDSA: "test-pub-ecdsa",
            pubKeyEdDSA: "test-pub-eddsa",
            keyshares: [],
            localPartyID: "party",
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    private func cosmosChainSpecific() -> BlockChainSpecific {
        .Cosmos(accountNumber: 1, sequence: 0, gas: 200_000, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil)
    }
}
