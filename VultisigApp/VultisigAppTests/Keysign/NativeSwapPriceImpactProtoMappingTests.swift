//
//  NativeSwapPriceImpactProtoMappingTests.swift
//  VultisigAppTests
//
//  Coverage for the native (THORChain / MayaChain) price impact carried on
//  `THORChainSwapPayload.slippageBps`. A co-signer holds no quote, and a quote
//  it fetched for itself would price a pool that has moved since the initiator
//  was quoted — which would make price impact the one term on the two verify
//  screens where two honest devices disagree. So it travels on the payload, and
//  these tests pin what goes on the wire, what an absent field means, and that
//  the string the joiner renders is the string the initiator renders.
//

import BigInt
import SwiftData
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class NativeSwapPriceImpactProtoMappingTests: XCTestCase {

    private var token: TestContextToken!

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(token)
        token = nil
    }

    // MARK: - Proto round-trip

    func testThorchainProtoRoundTripCarriesSlippageBps() throws {
        let proto = SwapPayload.thorchain(makeNativePayload(slippageBps: 125)).mapToProtobuff()
        guard case let .thorchainSwapPayload(value) = proto else {
            XCTFail("Expected .thorchainSwapPayload"); return
        }
        XCTAssertTrue(value.hasSlippageBps)
        XCTAssertEqual(value.slippageBps, 125)

        guard case let .thorchain(decoded) = try SwapPayload(proto: proto) else {
            XCTFail("Expected .thorchain"); return
        }
        XCTAssertEqual(decoded.slippageBps, 125)
    }

    func testMayachainProtoRoundTripCarriesSlippageBps() throws {
        let proto = SwapPayload.mayachain(makeNativePayload(slippageBps: 87)).mapToProtobuff()
        guard case let .mayachainSwapPayload(value) = proto else {
            XCTFail("Expected .mayachainSwapPayload"); return
        }
        XCTAssertTrue(value.hasSlippageBps)
        XCTAssertEqual(value.slippageBps, 87)

        guard case let .mayachain(decoded) = try SwapPayload(proto: proto) else {
            XCTFail("Expected .mayachain"); return
        }
        XCTAssertEqual(decoded.slippageBps, 87)
    }

    func testNilSlippageStaysOffTheWire() throws {
        let proto = SwapPayload.thorchain(makeNativePayload(slippageBps: nil)).mapToProtobuff()
        guard case let .thorchainSwapPayload(value) = proto else {
            XCTFail("Expected .thorchainSwapPayload"); return
        }
        XCTAssertFalse(
            value.hasSlippageBps,
            "An unknown impact must stay absent; a written 0 would claim a zero-impact route"
        )

        guard case let .thorchain(decoded) = try SwapPayload(proto: proto) else {
            XCTFail("Expected .thorchain"); return
        }
        XCTAssertNil(decoded.slippageBps)
    }

    /// The whole reason the field is `optional`: unlike the swap fee, a carried
    /// `0` is a real statement — the node quoted a zero-impact route — and it has
    /// to survive the wire as such rather than collapse into "unknown".
    func testZeroSlippageSurvivesTheWireAsAPresentZero() throws {
        let bytes = try protoBytes(for: makeNativePayload(slippageBps: 0))
        let reparsed = try VSTHORChainSwapPayload(serializedBytes: bytes)
        XCTAssertTrue(reparsed.hasSlippageBps, "A quoted zero is a claim, not an absence")

        let decoded = try SwapPayload(proto: .thorchainSwapPayload(reparsed))
        guard case let .thorchain(payload) = decoded else {
            XCTFail("Expected .thorchain"); return
        }
        XCTAssertEqual(payload.slippageBps, 0)
        XCTAssertEqual(decoded.priceImpact, 0)
        XCTAssertFalse(
            SwapCryptoLogic.priceImpactString(impact: decoded.priceImpact).isEmpty,
            "A zero-impact route renders a row; only an absent field hides one"
        )
    }

    func testLegacyWireBytesDecodeToNoImpactAndNoRow() throws {
        let reparsed = try VSTHORChainSwapPayload(serializedBytes: try makeLegacyProto().serializedData())
        let decoded = try SwapPayload(proto: .thorchainSwapPayload(reparsed))

        guard case let .thorchain(payload) = decoded else {
            XCTFail("Expected .thorchain"); return
        }
        XCTAssertNil(payload.slippageBps)
        XCTAssertNil(decoded.priceImpact)
        XCTAssertEqual(
            SwapCryptoLogic.priceImpactString(impact: decoded.priceImpact), .empty,
            "A sender predating the field says nothing about impact; hide the row"
        )
    }

    /// Byte-for-byte, not just "the field is unset". Mixed-version MPC committees
    /// depend on a relayed legacy payload re-serializing to the identical bytes;
    /// an assertion that only checks presence would survive a change that shifted
    /// any other field on the wire.
    func testReEncodingALegacyPayloadIsByteIdentical() throws {
        let originalBytes = try makeLegacyProto().serializedData()
        let decoded = try SwapPayload(proto: .thorchainSwapPayload(
            try VSTHORChainSwapPayload(serializedBytes: originalBytes)
        ))
        guard case let .thorchainSwapPayload(reEncoded) = decoded.mapToProtobuff() else {
            XCTFail("Expected .thorchainSwapPayload"); return
        }
        XCTAssertFalse(
            reEncoded.hasSlippageBps,
            "Relaying a legacy payload must not invent an impact its sender never stated"
        )
        // Message equality first: it names the offending field on failure, where
        // a raw byte comparison only reports that two blobs differ.
        XCTAssertEqual(
            reEncoded, try VSTHORChainSwapPayload(serializedBytes: originalBytes),
            "Re-encoding must not add, drop or rewrite any field"
        )
        XCTAssertEqual(
            try reEncoded.serializedData(), originalBytes,
            "A relayed legacy payload must re-serialize to the sender's exact bytes"
        )
    }

    /// A router that IS present must still travel — the presence fix must not
    /// turn into "never write the field".
    func testAPresentRouterAddressStillTravels() throws {
        var payload = makeNativePayload(slippageBps: nil)
        payload = THORChainSwapPayload(
            fromAddress: payload.fromAddress,
            fromCoin: payload.fromCoin,
            toCoin: payload.toCoin,
            vaultAddress: payload.vaultAddress,
            routerAddress: "0xrouter",
            fromAmount: payload.fromAmount,
            toAmountDecimal: payload.toAmountDecimal,
            toAmountLimit: payload.toAmountLimit,
            streamingInterval: payload.streamingInterval,
            streamingQuantity: payload.streamingQuantity,
            expirationTime: payload.expirationTime,
            isAffiliate: payload.isAffiliate
        )
        guard case let .thorchainSwapPayload(proto) = SwapPayload.thorchain(payload).mapToProtobuff() else {
            XCTFail("Expected .thorchainSwapPayload"); return
        }
        XCTAssertTrue(proto.hasRouterAddress)
        XCTAssertEqual(proto.routerAddress, "0xrouter")

        guard case let .thorchain(decoded) = try SwapPayload(proto: .thorchainSwapPayload(proto)) else {
            XCTFail("Expected .thorchain"); return
        }
        XCTAssertEqual(decoded.routerAddress, "0xrouter")
    }

    /// The reason the legacy round-trip was two bytes long: `router_address` is
    /// an `optional string`, so writing `""` for "no router" marks it present.
    func testAnAbsentRouterAddressStaysOffTheWire() {
        guard case let .thorchainSwapPayload(proto) =
                SwapPayload.thorchain(makeNativePayload(slippageBps: nil)).mapToProtobuff() else {
            XCTFail("Expected .thorchainSwapPayload"); return
        }
        XCTAssertFalse(
            proto.hasRouterAddress,
            "An absent router must not be written as a present empty string"
        )
    }

    // MARK: - What the builder puts on the wire

    func testBuilderCarriesTheQuotesSlippageBps() {
        XCTAssertEqual(
            SwapCryptoLogic.nativeSwapPayloadSlippageBps(quote: makeThorQuote(slippageBps: 125)),
            125
        )
        XCTAssertEqual(builtPayload(slippageBps: 125).slippageBps, 125)
    }

    /// The quote reports price impact in two places and they can differ. The one
    /// that has to travel is the one THIS device renders (`SwapQuote.priceImpact`
    /// reads the top-level field); carrying the nested `fees.slippage_bps` would
    /// show the co-signer a different number from the initiator, which is the one
    /// failure this field exists to prevent.
    func testBuilderCarriesTheTopLevelSlippageNotTheNestedFeeSlippage() {
        let quote = makeThorQuote(topLevel: 41, nested: 9)
        XCTAssertEqual(SwapCryptoLogic.nativeSwapPayloadSlippageBps(quote: quote), 41)

        let payload = SwapCryptoLogic.buildThorchainSwapPayload(
            fromCoin: makeBTC(),
            toCoin: makeTRX(),
            fromAmountInCoin: BigInt(100_000),
            toAmountDecimal: 3000,
            quote: quote
        )
        XCTAssertEqual(payload.slippageBps, 41)
        XCTAssertEqual(
            SwapPayload.thorchain(payload).priceImpact,
            SwapQuote.thorchain(quote).priceImpact,
            "Co-signer and initiator must read the same source"
        )
    }

    /// Presence follows the top-level field alone: a nested value with no
    /// top-level one is not a substitute.
    func testNestedFeeSlippageAloneCarriesNothing() {
        XCTAssertNil(
            SwapCryptoLogic.nativeSwapPayloadSlippageBps(quote: makeThorQuote(topLevel: nil, nested: 9))
        )
        XCTAssertNil(SwapQuote.thorchain(makeThorQuote(topLevel: nil, nested: 9)).priceImpact)
    }

    func testBuilderCarriesAQuotedZero() {
        XCTAssertEqual(SwapCryptoLogic.nativeSwapPayloadSlippageBps(quote: makeThorQuote(slippageBps: 0)), 0)
        XCTAssertEqual(builtPayload(slippageBps: 0).slippageBps, 0)
    }

    func testBuilderDropsAnAbsentSlippageBps() {
        XCTAssertNil(SwapCryptoLogic.nativeSwapPayloadSlippageBps(quote: makeThorQuote(slippageBps: nil)))
        XCTAssertNil(builtPayload(slippageBps: nil).slippageBps)
    }

    /// `slippage_bps` is a `uint32`. A negative would wrap into a ~4-billion-bps
    /// impact on the peer, which is worse than showing no row at all.
    func testBuilderDropsAnOutOfRangeSlippageBps() {
        for bps in [-1, -50, Int(UInt32.max) + 1] {
            XCTAssertNil(
                SwapCryptoLogic.nativeSwapPayloadSlippageBps(quote: makeThorQuote(slippageBps: bps)),
                "\(bps) does not fit a uint32 and must not be wrapped onto the wire"
            )
        }
    }

    // MARK: - What the co-signer renders

    /// The point of the change: the joiner's Price Impact row is the initiator's,
    /// arrived at from the serialized payload alone.
    func testCoSignerPriceImpactMatchesTheInitiatorsForTheSameQuote() throws {
        for bps in [0, 1, 99, 125, 305, 4_000] {
            let quote = makeThorQuote(slippageBps: bps)
            let initiatorQuote = SwapQuote.thorchain(quote)
            let payload = builtPayload(slippageBps: bps)
            // Through the wire, not just the in-memory struct — the device that
            // renders this row only ever sees the serialized bytes.
            let decoded = try SwapPayload(proto: .thorchainSwapPayload(
                try VSTHORChainSwapPayload(serializedBytes: try protoBytes(for: payload))
            ))

            let viewModel = JoinKeysignViewModel()
            viewModel.keysignPayload = makeKeysignPayload(swapPayload: decoded)

            XCTAssertEqual(
                viewModel.priceImpactString,
                SwapCryptoLogic.priceImpactString(quote: initiatorQuote),
                "Joiner and initiator must word \(bps) bps identically"
            )
            XCTAssertEqual(
                viewModel.priceImpactColor,
                SwapCryptoLogic.priceImpactColor(quote: initiatorQuote),
                "…and land in the same quality band"
            )
        }
    }

    func testCoSignerHidesTheRowForALegacySender() throws {
        let decoded = try SwapPayload(proto: .thorchainSwapPayload(
            try VSTHORChainSwapPayload(serializedBytes: try makeLegacyProto().serializedData())
        ))
        let viewModel = JoinKeysignViewModel()
        viewModel.keysignPayload = makeKeysignPayload(swapPayload: decoded)

        XCTAssertEqual(viewModel.priceImpactString, .empty)
    }

    func testChainnetAndStagenetVariantsSurfaceTheSameImpact() {
        let payload = makeNativePayload(slippageBps: 125)
        XCTAssertEqual(SwapPayload.thorchainChainnet(payload).priceImpact, Decimal(string: "0.0125"))
        XCTAssertEqual(SwapPayload.thorchainStagenet(payload).priceImpact, Decimal(string: "0.0125"))
        XCTAssertEqual(SwapPayload.mayachain(payload).priceImpact, Decimal(string: "0.0125"))
    }

    /// Aggregator routes put no impact on the keysign wire. Reporting one would
    /// mean re-deriving it here, which is exactly what this change refuses to do.
    func testAggregatorPayloadsCarryNoPriceImpact() {
        XCTAssertNil(SwapPayload.generic(makeGenericPayload()).priceImpact)
        XCTAssertNil(SwapPayload.swapkit(makeSwapKitPayload()).priceImpact)
    }

    // MARK: - Signing is untouched

    /// Display-only, asserted on the bytes rather than on a handful of fields.
    /// Clearing `slippage_bps` from a payload that carries it must reproduce the
    /// serialized bytes of a payload that never had it: that proves the field is
    /// purely additive and that nothing else on the wire — the memo terms, the
    /// vault address, the amounts a signer consumes — moved with it. A
    /// field-by-field comparison would pass even if an unlisted field had.
    func testCarriedImpactIsPurelyAdditiveOnTheWire() throws {
        guard case var .thorchainSwapPayload(withImpact) =
                SwapPayload.thorchain(builtPayload(slippageBps: 305)).mapToProtobuff(),
              case let .thorchainSwapPayload(withoutImpact) =
                SwapPayload.thorchain(builtPayload(slippageBps: nil)).mapToProtobuff() else {
            XCTFail("Expected .thorchainSwapPayload"); return
        }
        XCTAssertTrue(withImpact.hasSlippageBps, "…or this asserts nothing")
        XCTAssertNotEqual(try withImpact.serializedData(), try withoutImpact.serializedData())

        withImpact.clearSlippageBps()
        XCTAssertEqual(
            try withImpact.serializedData(), try withoutImpact.serializedData(),
            "The impact must be the ONLY difference these bytes carry"
        )
    }

    // MARK: - Fixtures

    private enum FixtureError: Error { case unexpectedProtoCase }

    private func protoBytes(for payload: THORChainSwapPayload) throws -> Data {
        guard case let .thorchainSwapPayload(value) = SwapPayload.thorchain(payload).mapToProtobuff() else {
            throw FixtureError.unexpectedProtoCase
        }
        return try value.serializedData()
    }

    private func builtPayload(slippageBps: Int?) -> THORChainSwapPayload {
        SwapCryptoLogic.buildThorchainSwapPayload(
            fromCoin: makeBTC(),
            toCoin: makeTRX(),
            fromAmountInCoin: BigInt(100_000),
            toAmountDecimal: 3000,
            quote: makeThorQuote(slippageBps: slippageBps)
        )
    }

    private func makeNativePayload(slippageBps: UInt32?) -> THORChainSwapPayload {
        THORChainSwapPayload(
            fromAddress: "bc1qsender",
            fromCoin: makeBTC(),
            toCoin: makeTRX(),
            vaultAddress: "bc1qasgard",
            routerAddress: nil,
            fromAmount: BigInt(100_000),
            toAmountDecimal: 3000,
            toAmountLimit: "0",
            streamingInterval: "1",
            streamingQuantity: "0",
            expirationTime: 1_757_000_000,
            isAffiliate: true,
            fee: nil,
            slippageBps: slippageBps
        )
    }

    /// Fields 1-12 only — the shape a sender that predates both field 13 and
    /// field 14 puts on the wire.
    private func makeLegacyProto() -> VSTHORChainSwapPayload {
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
        return legacy
    }

    private func makeGenericPayload() -> GenericSwapPayload {
        GenericSwapPayload(
            fromCoin: makeBTC(),
            toCoin: makeTRX(),
            fromAmount: BigInt(100_000),
            toAmountDecimal: 3000,
            quote: EVMQuote(
                dstAmount: "3000",
                tx: EVMQuote.Transaction(
                    from: "0xfrom", to: "0xto", data: "0x", value: "0",
                    gasPrice: "0", gas: 0, swapFee: "0", swapFeeTokenContract: ""
                )
            ),
            provider: .oneInch
        )
    }

    private func makeSwapKitPayload() -> SwapKitSwapPayload {
        SwapKitSwapPayload(
            fromCoin: makeBTC(),
            toCoin: makeTRX(),
            fromAmount: BigInt(100_000),
            toAmountDecimal: 3000,
            txType: "PSBT",
            txPayload: Data(),
            targetAddress: "bc1qtarget",
            inboundAddress: nil,
            memo: nil,
            subProvider: "NEAR",
            swapID: "swap-1"
        )
    }

    private func makeKeysignPayload(swapPayload: SwapPayload) -> KeysignPayload {
        KeysignPayload(
            coin: makeBTC(),
            toAddress: "bc1qasgard",
            toAmount: BigInt(100_000),
            chainSpecific: .UTXO(byteFee: BigInt(10), sendMaxAmount: false),
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

    /// Every fixture deliberately gives the quote's two price-impact sources
    /// DIFFERENT values. A fixture that set `slippage_bps` and
    /// `fees.slippage_bps` to the same number passes whichever one the builder
    /// happens to read — which is exactly how the wrong one shipped once.
    private func makeThorQuote(slippageBps: Int?) -> ThorchainSwapQuote {
        makeThorQuote(topLevel: slippageBps, nested: slippageBps.map { $0 + 7 })
    }

    private func makeThorQuote(topLevel: Int?, nested: Int?) -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "300000000000",
            expiry: 1_757_000_000,
            fees: Fees(
                affiliate: "0",
                asset: "TRX.TRX",
                outbound: "0",
                total: "0",
                liquidity: nil,
                slippageBps: nested,
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
            slippageBps: topLevel,
            totalSwapSeconds: nil,
            warning: "",
            router: nil,
            maxStreamingQuantity: nil
        )
    }

    private func makeBTC() -> Coin {
        makeCoin(.bitcoin, ticker: "BTC", decimals: 8)
    }

    private func makeTRX() -> Coin {
        makeCoin(.tron, ticker: "TRX", decimals: 6)
    }

    /// `RateProvider` is a process-wide singleton keyed by `priceProviderId`, so
    /// fixtures scope theirs to this class rather than sharing a generic id with
    /// other test classes.
    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int) -> Coin {
        let asset = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "logo",
            decimals: decimals,
            priceProviderId: "price-impact-5341-\(ticker.lowercased())",
            contractAddress: "",
            isNativeToken: true
        )
        return Coin(asset: asset, address: "price-impact-\(ticker)", hexPublicKey: "")
    }
}
