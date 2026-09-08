//
//  NativeSwapFeeProtoMappingTests.swift
//  VultisigAppTests
//
//  Native (THORChain / MayaChain) swap fee on `THORChainSwapPayload.fee`:
//  what reaches the wire, and that a co-signer reading only the payload
//  lands on the initiator's figure.
//

import BigInt
import SwiftData
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class NativeSwapFeeProtoMappingTests: XCTestCase {

    /// Rate fixtures write through `Storage.shared.modelContext`, which in a
    /// simulator can be the app's real store unless a container is installed.
    private var token: TestContextToken!

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(token)
        token = nil
    }

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

    func testKnownZeroFeeTravelsOnTheWire() throws {
        // A route that charges nothing is a statement, and the initiator renders
        // it as $0.00. Dropping it here is what left the co-signer with no row.
        let proto = SwapPayload.thorchain(makeNativePayload(fee: "0")).mapToProtobuff()
        guard case let .thorchainSwapPayload(value) = proto else {
            XCTFail("Expected .thorchainSwapPayload"); return
        }
        XCTAssertEqual(value.fee, "0")

        guard case let .thorchain(decoded) = try SwapPayload(proto: proto) else {
            XCTFail("Expected .thorchain"); return
        }
        XCTAssertEqual(decoded.fee, "0", "A stated zero must survive as a zero, not decay to nil")
    }

    /// `fee` has implicit presence, so unset and `"0"` are different bytes and must
    /// stay different UI. A change that rendered everything, or nothing, fails here.
    func testAbsentAndKnownZeroAreDistinguishableEndToEnd() throws {
        let model = JoinKeysignSwapFeeViewModel()

        let absent = try SwapPayload(proto: SwapPayload.thorchain(makeNativePayload(fee: nil)).mapToProtobuff())
        let zero = try SwapPayload(proto: SwapPayload.thorchain(makeNativePayload(fee: "0")).mapToProtobuff())

        XCTAssertNil(
            model.resolveSwapFee(swapPayload: absent, vault: nil),
            "A sender that stated nothing must render no row"
        )
        XCTAssertEqual(
            model.resolveSwapFee(swapPayload: zero, vault: nil)?.amount, 0,
            "A sender that stated zero must render a zero row, matching the initiator"
        )
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

    func testNativeSwapPayloadFeeIgnoresTheQuotesTotal() {
        // Varying ONLY `total` and pinning the exact result asserts independence;
        // a `!=` check would also be satisfied by an always-nil implementation.
        for total in ["60000000", "48000000", "0", "not-a-number"] {
            let quote = makeThorQuote(affiliate: "1000000", outbound: "47000000", total: total)
            XCTAssertEqual(
                SwapCryptoLogic.nativeSwapPayloadFee(quote: quote), "48000000",
                "fees.total = \(total) must not move the carried fee"
            )
        }
    }

    func testNativeSwapPayloadFeeIsZeroWhenNothingIsCharged() {
        // Same-chain routes (RUNE -> RUJI) have no outbound leg and can round the
        // affiliate cut to nothing. That is a fee of zero, not an absent fee.
        let quote = makeThorQuote(affiliate: "0", outbound: "0", total: "0")
        XCTAssertEqual(SwapCryptoLogic.nativeSwapPayloadFee(quote: quote), "0")
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

    func testNativeResolverYieldsNoRowOnlyForAnAbsentFee() {
        let model = JoinKeysignSwapFeeViewModel()
        XCTAssertNil(model.resolveSwapFee(swapPayload: .thorchain(makeNativePayload(fee: nil)), vault: nil))
        XCTAssertNil(model.resolveSwapFee(swapPayload: .thorchain(makeNativePayload(fee: "")), vault: nil))
        XCTAssertNil(
            model.resolveSwapFee(swapPayload: .thorchain(makeNativePayload(fee: "not-a-number")), vault: nil),
            "A malformed fee is unstatable, not zero"
        )
    }

    func testNativeResolverRendersAStatedZero() {
        let resolved = JoinKeysignSwapFeeViewModel().resolveSwapFee(
            swapPayload: .thorchain(makeNativePayload(fee: "0")),
            vault: nil
        )
        XCTAssertEqual(resolved?.amount, 0)
        XCTAssertEqual(resolved?.coin.ticker, "TRX")
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
        // Through the wire, not the in-memory struct: otherwise this still passes
        // when the proto writer stops writing the field.
        let decoded = try SwapPayload(proto: SwapPayload.thorchain(payload).mapToProtobuff())
        let resolved = try XCTUnwrap(
            JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: decoded, vault: nil)
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

        // Derived by hand, not from the code under test, so a wrong amount moves
        // the actual without moving the expectation.
        //   network: 21_000 gas x 1 gwei = 0.000021 ETH @ $2000 = $0.042
        //   swap:    0.48 TRX @ $0.25                           = $0.12
        XCTAssertEqual(
            JoinKeysignGasViewModel().networkFeeFiat(payload: keysignPayload),
            Decimal(string: "0.042"),
            "Network leg must price the transmitted gas through the payload's own coin"
        )
        XCTAssertEqual(
            viewModel.getSwapTotalFee(),
            Decimal(string: "0.162")?.formatToFiat(includeCurrencySymbol: true)
        )
    }

    func testTotalFeeRowPresentForAStatedZeroSwapFee() {
        // The RUNE -> RUJI shape: network fee only, but the row must still render
        // rather than vanish, because the initiator shows a total here.
        let sourceCoin = makeEthSource()
        setPrice(2000, for: sourceCoin)
        let viewModel = JoinKeysignViewModel()
        viewModel.keysignPayload = makeKeysignPayload(
            coin: sourceCoin,
            // Destination deliberately unpriced: a zero leg is worth zero at any
            // price, so it must not need a rate to enter the total.
            swapPayload: .thorchain(makeNativePayload(fee: "0", toCoin: makeUnpricedTRX()))
        )

        XCTAssertEqual(
            viewModel.getSwapTotalFee(),
            Decimal(string: "0.042")?.formatToFiat(includeCurrencySymbol: true),
            "A zero swap fee contributes zero; the total is the network fee alone"
        )
    }

    func testTotalFeeRowHiddenWhenTheSwapFeeCoinHasNoRate() throws {
        let sourceCoin = makeEthSource()
        setPrice(2000, for: sourceCoin)
        // Destination coin deliberately left unpriced.
        let viewModel = JoinKeysignViewModel()
        viewModel.keysignPayload = makeKeysignPayload(
            coin: sourceCoin,
            swapPayload: .thorchain(makeNativePayload(fee: "48000000", toCoin: makeUnpricedTRX()))
        )

        XCTAssertNotNil(
            JoinKeysignGasViewModel().networkFeeFiat(payload: try XCTUnwrap(viewModel.keysignPayload)),
            "Only the swap leg should be unpriced here, or this asserts the wrong branch"
        )
        XCTAssertNil(
            viewModel.getSwapTotalFee(),
            "An unpriced swap leg must drop the row, not be absorbed into the total as free"
        )
    }

    func testTotalFeeRowHiddenWhenTheNetworkFeeCoinHasNoRate() {
        // Source coin deliberately left unpriced.
        setPrice(0.25, for: makeTRX())
        let viewModel = JoinKeysignViewModel()
        viewModel.keysignPayload = makeKeysignPayload(
            coin: makeUnpricedEthSource(),
            swapPayload: .thorchain(makeNativePayload(fee: "48000000"))
        )

        XCTAssertNotNil(
            JoinKeysignSwapFeeViewModel().resolveSwapFee(
                swapPayload: viewModel.keysignPayload?.swapPayload, vault: nil
            ),
            "Only the network leg should be unpriced here, or this asserts the wrong branch"
        )
        XCTAssertNil(
            viewModel.getSwapTotalFee(),
            "An unpriced network leg must drop the row for the same reason"
        )
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

    private func makeEthSource() -> Coin {
        makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
    }

    /// Under an id nothing seeds, so the fail-closed branches see a real absence.
    private func makeUnpricedTRX() -> Coin {
        makeCoin(.tron, ticker: "TRX", decimals: 6, isNative: true, priceScope: "unpriced")
    }

    private func makeUnpricedEthSource() -> Coin {
        makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true, priceScope: "unpriced")
    }

    /// `RateProvider` is a process-wide singleton keyed by `priceProviderId`, so
    /// a generic id ("eth", "trx") would make this class and others order-dependent.
    private func makeCoin(
        _ chain: Chain,
        ticker: String,
        decimals: Int,
        isNative: Bool,
        contract: String = "",
        priceScope: String = "5340"
    ) -> Coin {
        let asset = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "logo",
            decimals: decimals,
            priceProviderId: "native-swap-fee-\(priceScope)-\(ticker.lowercased())",
            contractAddress: contract,
            isNativeToken: isNative
        )
        return Coin(asset: asset, address: "native-swap-fee-\(ticker)", hexPublicKey: "")
    }

    private func setPrice(
        _ value: Double,
        for coin: Coin,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let cryptoId = RateProvider.cryptoId(for: coin.toCoinMeta()).id
        // In-memory rates update before the storage write, so assert what the
        // tests depend on — that the rate reads back — not that the save landed.
        try? RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: cryptoId, value: value)
        ])
        XCTAssertNotNil(
            RateProvider.shared.rate(for: coin),
            "Seeded rate for \(coin.ticker) must be readable",
            file: file,
            line: line
        )
    }
}
