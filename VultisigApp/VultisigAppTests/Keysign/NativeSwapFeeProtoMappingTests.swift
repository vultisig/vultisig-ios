//
//  NativeSwapFeeProtoMappingTests.swift
//  VultisigAppTests
//
//  Coverage for the native (THORChain / MayaChain) swap fee on
//  `THORChainSwapPayload.fee`: what the builder puts on the wire, that a
//  legacy or zero fee stays off it, and that a co-signer rendering off the
//  payload alone lands on the initiator's own figure. A joiner holds no
//  quote, so this field is the only statement it gets of what the swap
//  costs — without it the confirm screen totals the network fee alone.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class NativeSwapFeeProtoMappingTests: XCTestCase {

    // MARK: - Proto round-trip

    func testThorchainProtoRoundTripCarriesFee() throws {
        let proto = SwapPayload.thorchain(makeNativePayload(fee: "48000000")).mapToProtobuff()
        guard case let .thorchainSwapPayload(value) = proto else {
            XCTFail("Expected .thorchainSwapPayload"); return
        }
        XCTAssertEqual(value.fee, "48000000")

        guard case let .thorchain(decoded) = try SwapPayload(proto: proto) else {
            XCTFail("Expected .thorchain"); return
        }
        XCTAssertEqual(decoded.fee, "48000000")
    }

    func testMayachainProtoRoundTripCarriesFee() throws {
        let payload = makeNativePayload(fee: "125000000000", toCoin: makeCacao())
        let proto = SwapPayload.mayachain(payload).mapToProtobuff()
        guard case let .mayachainSwapPayload(value) = proto else {
            XCTFail("Expected .mayachainSwapPayload"); return
        }
        XCTAssertEqual(value.fee, "125000000000")

        guard case let .mayachain(decoded) = try SwapPayload(proto: proto) else {
            XCTFail("Expected .mayachain"); return
        }
        XCTAssertEqual(decoded.fee, "125000000000")
    }

    func testNilFeeStaysOffTheWire() throws {
        let proto = SwapPayload.thorchain(makeNativePayload(fee: nil)).mapToProtobuff()
        guard case let .thorchainSwapPayload(value) = proto else {
            XCTFail("Expected .thorchainSwapPayload"); return
        }
        XCTAssertTrue(value.fee.isEmpty, "A sender with no quoted fee must leave the field unset")

        guard case let .thorchain(decoded) = try SwapPayload(proto: proto) else {
            XCTFail("Expected .thorchain"); return
        }
        XCTAssertNil(decoded.fee, "Empty on the wire normalizes back to nil, not \"\"")
    }

    func testZeroFeeStaysOffTheWire() {
        let proto = SwapPayload.thorchain(makeNativePayload(fee: "0")).mapToProtobuff()
        guard case let .thorchainSwapPayload(value) = proto else {
            XCTFail("Expected .thorchainSwapPayload"); return
        }
        XCTAssertTrue(value.fee.isEmpty, "A zero is indistinguishable from unknown; never claim it")
    }

    func testLegacyWireBytesDecodeToNoFeeAndNoRow() throws {
        // A sender that predates field 13 serializes fields 1-12 only.
        var legacy = VSTHORChainSwapPayload()
        legacy.fromAddress = "bc1qsender"
        legacy.fromCoin = ProtoCoinResolver.proto(from: makeBTC())
        legacy.toCoin = ProtoCoinResolver.proto(from: makeTRX())
        legacy.vaultAddress = "bc1qasgard"
        legacy.fromAmount = "100000"
        legacy.toAmountDecimal = "3000"
        legacy.toAmountLimit = "0"
        legacy.streamingInterval = "1"
        legacy.streamingQuantity = "0"
        legacy.expirationTime = 1_757_000_000
        legacy.isAffiliate = true

        let bytes = try legacy.serializedData()
        let reparsed = try VSTHORChainSwapPayload(serializedBytes: bytes)
        let decoded = try SwapPayload(proto: .thorchainSwapPayload(reparsed))

        guard case let .thorchain(payload) = decoded else {
            XCTFail("Expected .thorchain"); return
        }
        XCTAssertNil(payload.fee)
        XCTAssertNil(
            JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: decoded, vault: nil),
            "Legacy sender → render no row, never a definite $0.00"
        )
    }

    func testReEncodingALegacyPayloadLeavesTheFeeUnset() throws {
        var legacy = VSTHORChainSwapPayload()
        legacy.fromAddress = "bc1qsender"
        legacy.fromCoin = ProtoCoinResolver.proto(from: makeBTC())
        legacy.toCoin = ProtoCoinResolver.proto(from: makeTRX())
        legacy.vaultAddress = "bc1qasgard"
        legacy.fromAmount = "100000"
        legacy.toAmountDecimal = "3000"
        legacy.toAmountLimit = "0"
        legacy.streamingInterval = "1"
        legacy.streamingQuantity = "0"
        legacy.expirationTime = 1_757_000_000
        legacy.isAffiliate = true

        let decoded = try SwapPayload(proto: .thorchainSwapPayload(
            try VSTHORChainSwapPayload(serializedBytes: try legacy.serializedData())
        ))
        guard case let .thorchainSwapPayload(reEncoded) = decoded.mapToProtobuff() else {
            XCTFail("Expected .thorchainSwapPayload"); return
        }

        XCTAssertTrue(
            reEncoded.fee.isEmpty,
            "Relaying a legacy payload must not invent a fee the original sender never stated"
        )
    }

    // MARK: - What the builder puts on the wire

    func testNativeSwapPayloadFeeSumsAffiliateAndOutbound() {
        let quote = makeThorQuote(affiliate: "1000000", outbound: "47000000", total: "60000000")
        XCTAssertEqual(SwapCryptoLogic.nativeSwapPayloadFee(quote: quote), "48000000")
    }

    func testNativeSwapPayloadFeeExcludesTheLiquidityComponent() {
        // `fees.total` folds in the liquidity/slippage charge, which the quoted
        // output amount already reflects. Carrying it would make the co-signer's
        // total exceed the initiator's for the same swap.
        let quote = makeThorQuote(affiliate: "1000000", outbound: "47000000", total: "60000000")
        XCTAssertNotEqual(SwapCryptoLogic.nativeSwapPayloadFee(quote: quote), quote.fees.total)
    }

    func testNativeSwapPayloadFeeIsNilWhenNothingIsCharged() {
        let quote = makeThorQuote(affiliate: "0", outbound: "0", total: "0")
        XCTAssertNil(SwapCryptoLogic.nativeSwapPayloadFee(quote: quote))
    }

    func testNativeSwapPayloadFeeIsNilForAMalformedComponent() {
        let quote = makeThorQuote(affiliate: "1000000", outbound: "not-a-number", total: "60000000")
        XCTAssertNil(
            SwapCryptoLogic.nativeSwapPayloadFee(quote: quote),
            "A partial sum reads as authoritative; report nothing instead"
        )
    }

    func testBuiltThorchainPayloadCarriesTheQuoteFee() {
        let payload = SwapCryptoLogic.buildThorchainSwapPayload(
            fromCoin: makeBTC(),
            toCoin: makeTRX(),
            fromAmountInCoin: BigInt(100_000),
            toAmountDecimal: 3000,
            quote: makeThorQuote(affiliate: "1000000", outbound: "47000000", total: "60000000")
        )
        XCTAssertEqual(payload.fee, "48000000")
    }

    // MARK: - What the co-signer reads back

    func testNativeResolverScalesByThorchainFixedPoint() {
        // 48_000_000 @ 1e8 is 0.48 TRX — the destination asset, which is where
        // a native route charges. Reading it as raw units would be 1e8x off.
        let resolved = JoinKeysignSwapFeeViewModel().resolveSwapFee(
            swapPayload: .thorchain(makeNativePayload(fee: "48000000")),
            vault: nil
        )
        XCTAssertEqual(resolved?.amount, Decimal(string: "0.48"))
        XCTAssertEqual(resolved?.coin.ticker, "TRX", "Native fees are denominated in the destination coin")
    }

    func testNativeResolverScalesMayaDestinationByItsOwnDecimals() {
        // CACAO is 10-decimal, so MayaChain quotes it at 1e10, not THORChain's 1e8.
        let resolved = JoinKeysignSwapFeeViewModel().resolveSwapFee(
            swapPayload: .mayachain(makeNativePayload(fee: "125000000000", toCoin: makeCacao())),
            vault: nil
        )
        XCTAssertEqual(resolved?.amount, Decimal(string: "12.5"))
        XCTAssertEqual(resolved?.coin.ticker, "CACAO")
    }

    func testNativeResolverYieldsNoRowForZeroOrAbsentFee() {
        let model = JoinKeysignSwapFeeViewModel()
        XCTAssertNil(model.resolveSwapFee(swapPayload: .thorchain(makeNativePayload(fee: nil)), vault: nil))
        XCTAssertNil(model.resolveSwapFee(swapPayload: .thorchain(makeNativePayload(fee: "0")), vault: nil))
        XCTAssertNil(model.resolveSwapFee(swapPayload: .thorchain(makeNativePayload(fee: "")), vault: nil))
    }

    func testChainnetAndStagenetVariantsResolveTheSameFee() {
        let model = JoinKeysignSwapFeeViewModel()
        let payload = makeNativePayload(fee: "48000000")
        XCTAssertEqual(
            model.resolveSwapFee(swapPayload: .thorchainChainnet(payload), vault: nil)?.amount,
            Decimal(string: "0.48")
        )
        XCTAssertEqual(
            model.resolveSwapFee(swapPayload: .thorchainStagenet(payload), vault: nil)?.amount,
            Decimal(string: "0.48")
        )
    }

    /// The point of the whole change: the fiat the co-signer shows is the fiat
    /// the initiator itemizes, arrived at from the payload alone.
    func testCoSignerSwapFeeFiatMatchesTheInitiatorItemization() throws {
        let fromCoin = makeBTC()
        let toCoin = makeTRX()
        setPrice(0.25, for: toCoin)
        let quote = makeThorQuote(affiliate: "1000000", outbound: "47000000", total: "60000000")
        let swapQuote = SwapQuote.thorchain(quote)

        let initiatorFiat = SwapCryptoLogic.affiliateFeeFiat(
            quote: swapQuote, fromCoin: fromCoin, toCoin: toCoin, feeCoin: fromCoin
        ) + SwapCryptoLogic.outboundFeeFiat(quote: swapQuote, toCoin: toCoin)

        let payload = SwapCryptoLogic.buildThorchainSwapPayload(
            fromCoin: fromCoin,
            toCoin: toCoin,
            fromAmountInCoin: BigInt(100_000),
            toAmountDecimal: 3000,
            quote: quote
        )
        let resolved = try XCTUnwrap(
            JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: .thorchain(payload), vault: nil)
        )

        XCTAssertGreaterThan(initiatorFiat, 0, "Seeded rate should make the comparison meaningful")
        XCTAssertEqual(toCoin.fiat(decimal: resolved.amount), initiatorFiat)
    }

    // MARK: - Total-fee row on the co-signer's confirm screen

    func testTotalFeeRowSumsNetworkAndSwapFee() throws {
        let sourceCoin = makeEthSource()
        setPrice(2000, for: sourceCoin)
        let toCoin = makeTRX()
        setPrice(0.25, for: toCoin)

        let keysignPayload = makeKeysignPayload(
            coin: sourceCoin,
            swapPayload: .thorchain(makeNativePayload(fee: "48000000", toCoin: toCoin))
        )
        let viewModel = JoinKeysignViewModel()
        viewModel.keysignPayload = keysignPayload

        let networkFiat = try XCTUnwrap(JoinKeysignGasViewModel().networkFeeFiat(payload: keysignPayload))
        let expected = (networkFiat + toCoin.fiat(decimal: Decimal(string: "0.48") ?? 0))
            .formatToFiat(includeCurrencySymbol: true)

        XCTAssertEqual(viewModel.getSwapTotalFee(), expected)
    }

    func testTotalFeeRowHiddenWhenTheSenderCarriedNoFee() {
        let sourceCoin = makeEthSource()
        setPrice(2000, for: sourceCoin)
        setPrice(0.25, for: makeTRX())

        let viewModel = JoinKeysignViewModel()
        viewModel.keysignPayload = makeKeysignPayload(
            coin: sourceCoin,
            swapPayload: .thorchain(makeNativePayload(fee: nil))
        )

        XCTAssertNil(
            viewModel.getSwapTotalFee(),
            "A legacy payload is indistinguishable from a free route; a network-fee-only total is the bug"
        )
    }

    // MARK: - Fixtures

    private func makeNativePayload(fee: String?, toCoin: Coin? = nil) -> THORChainSwapPayload {
        THORChainSwapPayload(
            fromAddress: "bc1qsender",
            fromCoin: makeBTC(),
            toCoin: toCoin ?? makeTRX(),
            vaultAddress: "bc1qasgard",
            routerAddress: nil,
            fromAmount: BigInt(100_000),
            toAmountDecimal: 3000,
            toAmountLimit: "0",
            streamingInterval: "1",
            streamingQuantity: "0",
            expirationTime: 1_757_000_000,
            isAffiliate: true,
            fee: fee
        )
    }

    private func makeKeysignPayload(coin: Coin, swapPayload: SwapPayload) -> KeysignPayload {
        KeysignPayload(
            coin: coin,
            toAddress: "0xasgard",
            toAmount: BigInt("1000000000000000000"),
            chainSpecific: .Ethereum(
                maxFeePerGasWei: BigInt(1_000_000_000),
                priorityFeeWei: 0,
                nonce: 0,
                gasLimit: BigInt(21_000)
            ),
            utxos: [],
            memo: "=:TRX.TRX:addr",
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

    private func makeThorQuote(affiliate: String, outbound: String, total: String) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "300000000000",
            expiry: 1_757_000_000,
            fees: Fees(
                affiliate: affiliate,
                asset: "TRX.TRX",
                outbound: outbound,
                total: total,
                liquidity: nil,
                slippageBps: nil,
                totalBps: nil
            ),
            inboundAddress: "bc1qasgard",
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: "=:TRX.TRX:addr:0/1/0",
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

    private func makeBTC() -> Coin {
        makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
    }

    private func makeTRX() -> Coin {
        makeCoin(.tron, ticker: "TRX", decimals: 6, isNative: true)
    }

    private func makeCacao() -> Coin {
        makeCoin(.mayaChain, ticker: "CACAO", decimals: 10, isNative: true)
    }

    /// A distinct ticker (and so a distinct price-provider id) keeps the source
    /// coin's seeded rate independent of whatever another test class priced ETH at.
    private func makeEthSource() -> Coin {
        makeCoin(.ethereum, ticker: "ETHNATIVEFEE", decimals: 18, isNative: true)
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
        return Coin(asset: asset, address: "native-swap-fee-\(ticker)", hexPublicKey: "")
    }

    private func setPrice(_ value: Double, for coin: Coin) {
        let cryptoId = RateProvider.cryptoId(for: coin.toCoinMeta()).id
        // In-memory rates update before the storage write, so a storage failure
        // in the test harness doesn't invalidate the assertion.
        try? RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: cryptoId, value: value)
        ])
    }
}
