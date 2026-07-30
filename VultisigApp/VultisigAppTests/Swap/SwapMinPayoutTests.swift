//
//  SwapMinPayoutTests.swift
//  VultisigAppTests
//
//  Pins the "min. payout" the swap screens show to the `LIM` inside the memo
//  the swap is actually SIGNED with. The invariant under test is one sentence:
//  a number labelled *minimum* must be a number the broadcast transaction
//  enforces — never the quote's expected output, and never a client-side
//  re-derivation from the slippage tolerance we sent.
//
//  Routes that enforce no floor this app can read (every aggregator, a memo
//  whose LIM is 0) must surface `nil` so the caller renders no minimum at all.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapMinPayoutTests: XCTestCase {

    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    /// The exact memo signed by the broadcast in the bug report: RUNE → ETH,
    /// 2 RUNE, THORChain, `liquidity_tolerance_bps` at its 100 bps default.
    private let reportedMemo = "=:e:0x15E9eBd862E8d7cd571062D0fBd41D695A9575AF:32334:vi:0"
    /// `expected_amount_out` from the same quote — 1.0% above the memo's floor,
    /// and the value the screen used to render under the "min. payout" label.
    private let reportedExpectedAmountOut = "32658"

    // MARK: - Displayed minimum == LIM in the signed memo

    func testDisplayedMinimumEqualsLimitInTheSignedMemo() async throws {
        let transaction = makeRuneToEthTransaction(
            quote: makeThorQuote(memo: reportedMemo, expectedAmountOut: reportedExpectedAmountOut)
        )

        let payload = try await SwapCryptoLogic.buildSwapKeysignPayload(
            transaction: transaction,
            chainSpecific: cosmosChainSpecific(),
            vault: makeVault(),
            now: fixedNow
        )

        // The memo that will be signed, byte-for-byte.
        XCTAssertEqual(payload.memo, reportedMemo)

        let signedLimit = try XCTUnwrap(ThorchainMemoLimit.assertedLimit(in: try XCTUnwrap(payload.memo)))
        XCTAssertEqual(signedLimit, BigInt(32_334))

        // What the destination cell renders under "min. payout", scaled back into
        // the node's base units, is that same LIM — not an approximation of it.
        let displayed = try XCTUnwrap(transaction.minPayoutDecimal)
        XCTAssertEqual(displayed * transaction.toCoin.thorswapMultiplier, baseUnits(signedLimit))
        XCTAssertEqual(displayed, Decimal(string: "0.00032334"))
    }

    func testDisplayedMinimumIsBelowTheExpectedOutputItUsedToDuplicate() throws {
        let transaction = makeRuneToEthTransaction(
            quote: makeThorQuote(memo: reportedMemo, expectedAmountOut: reportedExpectedAmountOut)
        )

        // The regression this fixes: the cell showed the expected output under a
        // "minimum" label. The two must now be distinct values.
        XCTAssertEqual(transaction.toAmountDecimal, Decimal(string: "0.00032658"))
        let minimum = try XCTUnwrap(transaction.minPayoutDecimal)
        XCTAssertEqual(minimum, Decimal(string: "0.00032334"))
        XCTAssertLessThan(minimum, transaction.toAmountDecimal)
    }

    // MARK: - Custom slippage

    func testCustomSlippageMinimumTracksTheMemoNotTheDefaultTolerance() {
        // A 3% `liquidity_tolerance_bps` produces a lower node-chosen LIM in the
        // same-shaped memo. Nothing in the app re-derives it, so the displayed
        // floor moves with the memo alone — which is the only way it can stay
        // equal to what is signed on a non-default slippage.
        let customSlippageMemo = "=:e:0x15E9eBd862E8d7cd571062D0fBd41D695A9575AF:31678:vi:0"
        let transaction = makeRuneToEthTransaction(
            quote: makeThorQuote(memo: customSlippageMemo, expectedAmountOut: reportedExpectedAmountOut)
        )

        XCTAssertEqual(transaction.minPayoutDecimal, Decimal(string: "0.00031678"))
        // Same quote, same expected output — only the memo changed.
        XCTAssertEqual(transaction.toAmountDecimal, Decimal(string: "0.00032658"))
    }

    func testZeroSlippageMemoAssertsNoFloorSoNoMinimumIsShown() {
        // A user-set 0% slippage omits `liquidity_tolerance_bps` entirely, and
        // the node then returns `LIM 0` — a swap with genuinely no floor. The
        // screen must show no minimum rather than fall back to the expected out.
        let transaction = makeRuneToEthTransaction(
            quote: makeThorQuote(
                memo: "=:e:0x15E9eBd862E8d7cd571062D0fBd41D695A9575AF:0/1/0:vi:0",
                expectedAmountOut: reportedExpectedAmountOut
            )
        )

        XCTAssertNil(transaction.minPayoutDecimal)
        XCTAssertNil(transaction.minPayoutCaption)
    }

    // MARK: - UTXO source: the signed memo is the compressed one

    func testUtxoSourceMinimumFollowsTheCompressedMemoNotTheQuoteMemo() throws {
        // 81 bytes — over the 80-byte OP_RETURN cap, so the payload builder
        // rewrites the LIM into scientific notation, rounding DOWN, before it is
        // signed. The proto's `toAmountLimit` is read from the *quote* memo and
        // therefore overstates the real floor; the display must not.
        let overflowMemo = "=:ETH.USDC:0x742d35Cc6634C0532925a3b844Bc454e4438f44e:653422929721250/0/224:vi:50"
        XCTAssertEqual(overflowMemo.utf8.count, 81, "Precondition: memo overflows the OP_RETURN cap")

        let quote = makeThorQuote(memo: overflowMemo, expectedAmountOut: "660000000000000")
        let transaction = makeBtcToUsdcTransaction(quote: quote)

        let signedMemo = ThorchainMemoLimit.signedMemo(overflowMemo, sourceChain: .bitcoin)
        XCTAssertNotEqual(signedMemo, overflowMemo, "Precondition: compression fired")
        let signedLimit = try XCTUnwrap(ThorchainMemoLimit.assertedLimit(in: signedMemo))

        let displayed = try XCTUnwrap(transaction.minPayoutDecimal)
        XCTAssertEqual(displayed * transaction.toCoin.thorswapMultiplier, baseUnits(signedLimit))

        // And it is strictly below the floor the proto field claims.
        let protoLimit = SwapCryptoLogic.buildThorchainSwapPayload(
            fromCoin: transaction.fromCoin,
            toCoin: transaction.toCoin,
            fromAmountInCoin: BigInt(20_000_000_000),
            toAmountDecimal: transaction.toAmountDecimal,
            quote: quote,
            now: fixedNow
        ).toAmountLimit
        XCTAssertEqual(protoLimit, "653422929721250")
        XCTAssertLessThan(
            displayed * transaction.toCoin.thorswapMultiplier,
            try XCTUnwrap(Decimal(string: protoLimit))
        )
    }

    // MARK: - Routes that enforce no readable floor

    func testAggregatorRoutesShowNoMinimum() {
        let evmQuote = EVMQuote(
            dstAmount: "1000000000000000000",
            tx: EVMQuote.Transaction(from: "0xFrom", to: "0xRouter", data: "0x", value: "0", gasPrice: "0", gas: 0)
        )
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)

        // 1inch / KyberSwap / LI.FI / Jupiter hand back opaque calldata or a
        // pre-built transaction; SwapKit settles off the source chain. None of
        // them exposes a floor the signed transaction enforces, so none may
        // claim one.
        let quotes: [SwapQuote] = [
            .oneinch(evmQuote, fee: nil),
            .kyberswap(evmQuote, fee: nil),
            .lifi(evmQuote, fee: nil, integratorFee: nil),
            .jupiter(evmQuote, fee: nil, platformFee: 0, feeOnInput: false),
            .swapkit(makeSwapKitResponse(), fee: nil, subProvider: "Chainflip")
        ]
        for quote in quotes {
            XCTAssertNil(
                SwapCryptoLogic.signedMinimumOutput(quote: quote, fromCoin: eth, toCoin: usdc),
                "Aggregator route \(quote.kind) must not claim a minimum"
            )
        }
    }

    func testSecuredMintShowsNoMinimum() {
        // The synthetic ~1:1 mint quote carries no memo — nothing is enforced,
        // the mint settles at the on-chain share ratio.
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        let securedBtc = makeCoin(.thorChain, ticker: "BTC-BTC", decimals: 8, isNative: false)
        let quote = SwapCryptoLogic.securedMintQuote(fromAmount: 1, toCoin: securedBtc)

        XCTAssertNil(SwapCryptoLogic.signedMinimumOutput(quote: quote, fromCoin: btc, toCoin: securedBtc))
    }

    func testLimitOrderShowsNoSeparateMinimumBecauseItsAmountAlreadyIsOne() {
        // A placed `=<` order's own destination amount IS the floor, so the
        // "min. payout" caption already tells the truth and a second line
        // restating it would be noise.
        let transaction = makeLimitTransaction()

        XCTAssertTrue(transaction.isLimit)
        XCTAssertNil(transaction.minPayoutDecimal)
    }

    func testNilQuoteShowsNoMinimum() {
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        XCTAssertNil(SwapCryptoLogic.signedMinimumOutput(quote: nil, fromCoin: eth, toCoin: eth))
    }

    // MARK: - MayaChain scaling

    func testMayachainMinimumUsesTheDestinationCoinsOwnPrecision() {
        // Maya quotes CACAO in its native 10 decimals, not THORChain's 1e8, so
        // the floor must be scaled by the same multiplier the expected amount is.
        let cacao = makeCoin(.mayaChain, ticker: "CACAO", decimals: 10, isNative: true)
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        let quote = SwapQuote.mayachain(makeThorQuote(
            memo: "=:MAYA.CACAO:maya1qz8p9dxq4l7wg2m4vtn5xq6r3jf0h8u2vk9c7d:12345678901/0/0",
            expectedAmountOut: "12469372627"
        ))

        XCTAssertEqual(
            SwapCryptoLogic.signedMinimumOutput(quote: quote, fromCoin: btc, toCoin: cacao),
            Decimal(string: "1.2345678901")
        )
    }

    // MARK: - Memo parsing

    func testAssertedLimitReadsBothCanonicalSpellings() {
        XCTAssertEqual(ThorchainMemoLimit.assertedLimit(in: "=:e:0xabc:32334:vi:0"), BigInt(32_334))
        XCTAssertEqual(ThorchainMemoLimit.assertedLimit(in: "=:e:0xabc:32334/1/3:vi:0"), BigInt(32_334))
        // Scientific notation is what `compressed(_:maxBytes:)` substitutes for a
        // UTXO source; the chain reads it as `mantissa` + `exponent` zeros.
        XCTAssertEqual(ThorchainMemoLimit.assertedLimit(in: "=:e:0xabc:653422929721e3/0/224:vi:50"), BigInt("653422929721000"))
        // Both other spellings of the swap action, case-insensitively.
        XCTAssertEqual(ThorchainMemoLimit.assertedLimit(in: "SWAP:e:0xabc:500"), BigInt(500))
        XCTAssertEqual(ThorchainMemoLimit.assertedLimit(in: "s:e:0xabc:500"), BigInt(500))
    }

    func testAssertedLimitRefusesAnythingItCannotVouchFor() {
        let cases = [
            "=:e:0xabc:0/1/0",                 // no floor asserted
            "=:e:0xabc:0",                     // no floor, short memo
            "=:e:0xabc",                       // fewer than four fields
            "",                                // empty
            "ADD:BTC.BTC:0xabc:12345",         // not a swap action — 4th field is not a LIM
            "LOAN+:BTC.BTC:0xabc:12345",       // ditto
            "=:e:0xabc:notanumber/1/0",        // unreadable term
            "=:e:0xabc:-500/1/0",              // signed
            "=:e:0xabc:1.5/1/0",               // fractional
            "=:e:0xabc:١٢٣/1/0",               // non-ASCII numerals
            "=:e:0xabc:12e/1/0",               // empty exponent
            "=:e:0xabc:e5/1/0",                // empty mantissa
            "=:e:0xabc:12e5e5/1/0",            // two exponents
            "=:e:0xabc:1e999999/1/0",          // exponent beyond what we will expand
            "=:e:0xabc: 12345/1/0"             // leading whitespace — not canonical
        ]
        for memo in cases {
            XCTAssertNil(ThorchainMemoLimit.assertedLimit(in: memo), "Must refuse to read a floor from: \(memo)")
        }
    }

    // MARK: - Co-signer

    /// The WYSIWYS half: the peer approving the swap must see the floor that the
    /// memo IT is about to sign carries, not the initiator's expected output.
    func testCosignerMinimumEqualsTheLimitInTheMemoItSigns() throws {
        let viewModel = makeJoinViewModel(
            memo: reportedMemo,
            swapPayload: .thorchain(makeThorchainSwapPayload())
        )

        XCTAssertEqual(viewModel.toAmountCaptionKey, "expectedPayout")
        XCTAssertEqual(
            viewModel.getMinPayoutCaption(),
            SwapCryptoLogic.minPayoutCaption(amount: try XCTUnwrap(Decimal(string: "0.00032334")), ticker: "ETH")
        )
    }

    func testCosignerShowsNoMinimumForAnAggregatorRoute() {
        // A generic payload signs opaque calldata and carries no memo at all.
        let viewModel = makeJoinViewModel(memo: nil, swapPayload: .generic(makeGenericSwapPayload()))

        XCTAssertEqual(viewModel.toAmountCaptionKey, "expectedPayout")
        XCTAssertNil(viewModel.getMinPayoutCaption())
    }

    /// An ERC20-source limit order reaches the co-signer as a swap payload whose
    /// `toAmountDecimal` the assembler already set to the order's LIM. Its
    /// caption must stay "min. payout", and a second line restating the same
    /// number would be noise.
    func testCosignerKeepsTheMinimumCaptionForALimitOrder() {
        let viewModel = makeJoinViewModel(
            memo: "=<:ETH.ETH:0x15E9eBd862E8d7cd571062D0fBd41D695A9575AF:32000/1/0:vi:50",
            swapPayload: .thorchain(makeThorchainSwapPayload())
        )

        XCTAssertEqual(viewModel.toAmountCaptionKey, "minPayout")
        XCTAssertNil(viewModel.getMinPayoutCaption())
    }

    func testNativeProtocolRouteIsTheOnlyPayloadKindThatCanCarryAFloor() {
        let native = makeThorchainSwapPayload()
        for payload in [
            SwapPayload.thorchain(native),
            .thorchainChainnet(native),
            .thorchainStagenet(native),
            .mayachain(native)
        ] {
            XCTAssertTrue(payload.isNativeProtocolRoute)
        }
        XCTAssertFalse(SwapPayload.generic(makeGenericSwapPayload()).isNativeProtocolRoute)
    }

    // MARK: - Caption

    func testMinPayoutCaptionCarriesTheAmountAndTicker() throws {
        let transaction = makeRuneToEthTransaction(
            quote: makeThorQuote(memo: reportedMemo, expectedAmountOut: reportedExpectedAmountOut)
        )
        let caption = try XCTUnwrap(transaction.minPayoutCaption)

        XCTAssertTrue(caption.hasSuffix("0.00032334 ETH"), "Got: \(caption)")
        XCTAssertEqual(
            caption,
            SwapCryptoLogic.minPayoutCaption(amount: try XCTUnwrap(Decimal(string: "0.00032334")), ticker: "ETH"),
            "Initiator and co-signer must render one identical string"
        )
    }

    // MARK: - Fixtures

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

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }

    private func makeRuneToEthTransaction(quote: ThorchainSwapQuote) -> SwapTransaction {
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        return SwapTransaction(
            fromCoin: rune,
            toCoin: eth,
            fromAmount: 2.0,
            kind: .market(.thorchain(quote)),
            gas: 0,
            gasLimit: 0,
            thorchainFee: BigInt(2_000),
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: rune,
            advancedSettings: .default
        )
    }

    private func makeBtcToUsdcTransaction(quote: ThorchainSwapQuote) -> SwapTransaction {
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        return SwapTransaction(
            fromCoin: btc,
            toCoin: usdc,
            fromAmount: 200,
            kind: .market(.thorchain(quote)),
            gas: 0,
            gasLimit: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: btc,
            advancedSettings: .default
        )
    }

    private func makeLimitTransaction() -> SwapTransaction {
        let rune = makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let record = LimitOrderRecord(
            inboundTxHash: "",
            sourceAsset: "THOR.RUNE",
            sourceAmount: "200000000",
            sourceDecimals: 8,
            targetAsset: "ETH.ETH",
            destAddress: "0x15E9eBd862E8d7cd571062D0fBd41D695A9575AF",
            targetPrice: Decimal(string: "0.00016") ?? 0,
            expiryBlocks: 14_400,
            createdAt: fixedNow,
            memo: "=<:ETH.ETH:0x15E9eBd862E8d7cd571062D0fBd41D695A9575AF:32000",
            expiryHours: 24
        )
        return SwapTransaction(
            fromCoin: rune,
            toCoin: eth,
            fromAmount: 2.0,
            kind: .limit(record),
            gas: 0,
            gasLimit: 0,
            thorchainFee: 0,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: rune,
            advancedSettings: .default
        )
    }

    private func makeThorQuote(memo: String, expectedAmountOut: String) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: expectedAmountOut,
            expiry: 0,
            fees: Fees(affiliate: "0", asset: "ETH", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
            inboundAddress: "thor-vault",
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: memo,
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            slippageBps: nil,
            totalSwapSeconds: nil,
            warning: "",
            router: nil,
            maxStreamingQuantity: nil
        )
    }

    /// `Decimal(_: BigInt)` is ambiguous from the test target, so spell the
    /// base-unit conversion out once.
    private func baseUnits(_ limit: BigInt) -> Decimal {
        Decimal(string: String(limit)) ?? .nan
    }

    private func makeJoinViewModel(memo: String?, swapPayload: SwapPayload) -> JoinKeysignViewModel {
        let viewModel = JoinKeysignViewModel()
        viewModel.keysignPayload = KeysignPayload(
            coin: makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true),
            toAddress: "thor-vault",
            toAmount: BigInt(200_000_000),
            chainSpecific: cosmosChainSpecific(),
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
        return viewModel
    }

    private func makeThorchainSwapPayload() -> THORChainSwapPayload {
        THORChainSwapPayload(
            fromAddress: "test-address-RUNE",
            fromCoin: makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true),
            toCoin: makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true),
            vaultAddress: "thor-vault",
            routerAddress: nil,
            fromAmount: BigInt(200_000_000),
            toAmountDecimal: Decimal(string: "0.00032658") ?? 0,
            toAmountLimit: "32334",
            streamingInterval: "0",
            streamingQuantity: "0",
            expirationTime: 0,
            isAffiliate: true
        )
    }

    private func makeGenericSwapPayload() -> GenericSwapPayload {
        GenericSwapPayload(
            fromCoin: makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false),
            toCoin: makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true),
            fromAmount: BigInt(100_000_000),
            toAmountDecimal: 1,
            quote: EVMQuote(
                dstAmount: "1000000000000000000",
                tx: EVMQuote.Transaction(from: "0xFrom", to: "0xRouter", data: "0x", value: "0", gasPrice: "0", gas: 0)
            ),
            provider: .oneInch
        )
    }

    private func cosmosChainSpecific() -> BlockChainSpecific {
        .Cosmos(accountNumber: 1, sequence: 0, gas: 200_000, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil)
    }

    /// `SwapKitSwapResponse` is `Decodable`-only, so build it from JSON.
    /// `expectedBuyAmountMaxSlippage` is populated on purpose: SwapKit DOES
    /// publish a worst-case figure, and this pins that we still refuse to call
    /// it a minimum — it is the provider's estimate for a route that settles
    /// off the source chain, not something the transaction we sign enforces.
    private func makeSwapKitResponse() -> SwapKitSwapResponse {
        let json = """
        {
          "swapId": "swap-1",
          "routeId": "route-1",
          "providers": ["Chainflip"],
          "sellAsset": "ETH.USDC",
          "buyAsset": "ETH.ETH",
          "sellAmount": "10",
          "expectedBuyAmount": "1.0",
          "expectedBuyAmountMaxSlippage": "0.97",
          "sourceAddress": "0xfrom",
          "destinationAddress": "0xto",
          "targetAddress": "0xtarget",
          "meta": { "txType": "EVM" },
          "tx": {
            "from": "0xfrom",
            "to": "0xto",
            "value": "0",
            "data": "0x",
            "gas": "200000",
            "gasPrice": "20000000000"
          },
          "fees": []
        }
        """
        // Test fixture: a decode failure here is a test bug, so force-try is acceptable.
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(SwapKitSwapResponse.self, from: Data(json.utf8))
    }
}
