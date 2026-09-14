//
//  SwapKitSwapFeeProtoMappingTests.swift
//  VultisigAppTests
//
//  Coverage for the provider fee on `SwapKitSwapPayload` (swap_fee plus the
//  chain / token id / decimals naming its coin): the wire shape, the never-guess
//  resolution, and that an absent field reads as "unknown" rather than zero.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SwapKitSwapFeeProtoMappingTests: XCTestCase {

    // MARK: - Proto round-trip

    func testProtoRoundTripCarriesFeeAndCoinContext() throws {
        let payload = makeSwapKitPayload(
            swapFee: "250000",
            swapFeeChain: Chain.bitcoinCash.name,
            swapFeeTokenId: nil,
            swapFeeDecimals: 8
        )
        let proto = SwapPayload.swapkit(payload).mapToProtobuff()
        guard case let .swapkitSwapPayload(value) = proto else {
            XCTFail("Expected .swapkitSwapPayload"); return
        }
        XCTAssertEqual(value.swapFee, "250000")
        XCTAssertTrue(value.hasSwapFeeChain)
        XCTAssertEqual(value.swapFeeChain, Chain.bitcoinCash.name)
        XCTAssertFalse(value.hasSwapFeeTokenID, "A native fee names no token")
        XCTAssertTrue(value.hasSwapFeeDecimals)
        XCTAssertEqual(value.swapFeeDecimals, 8)

        guard case let .swapkit(decoded) = try SwapPayload(proto: proto) else {
            XCTFail("Expected .swapkit"); return
        }
        XCTAssertEqual(decoded.swapFee, "250000")
        XCTAssertEqual(decoded.swapFeeChain, Chain.bitcoinCash.name)
        XCTAssertNil(decoded.swapFeeTokenId)
        XCTAssertEqual(decoded.swapFeeDecimals, 8)
    }

    func testProtoRoundTripCarriesATokenDenominatedFee() throws {
        let payload = makeSwapKitPayload(
            swapFee: "150000",
            swapFeeChain: "Ethereum",
            swapFeeTokenId: usdcContract,
            swapFeeDecimals: 6
        )
        guard case let .swapkit(decoded) = try SwapPayload(
            proto: SwapPayload.swapkit(payload).mapToProtobuff()
        ) else {
            XCTFail("Expected .swapkit"); return
        }
        XCTAssertEqual(decoded.swapFeeTokenId, usdcContract)
        XCTAssertEqual(decoded.swapFeeDecimals, 6)
    }

    func testNilFeeLeavesTheWholeGroupOffTheWire() throws {
        let payload = makeSwapKitPayload(
            swapFee: nil,
            swapFeeChain: Chain.bitcoinCash.name,
            swapFeeTokenId: nil,
            swapFeeDecimals: 8
        )
        guard case let .swapkitSwapPayload(value) = SwapPayload.swapkit(payload).mapToProtobuff() else {
            XCTFail("Expected .swapkitSwapPayload"); return
        }
        XCTAssertTrue(value.swapFee.isEmpty)
        XCTAssertFalse(
            value.hasSwapFeeChain,
            "Coin context without an amount describes nothing; it must not travel alone"
        )
        XCTAssertFalse(value.hasSwapFeeDecimals)
    }

    /// `swap_fee` is optional on this payload, so `nil` is "absent" and `"0"` is
    /// a sender stating the route charges nothing. `"0"` is a non-empty string
    /// and does serialize, so the claim survives the wire and must not be
    /// collapsed into absence on the way out.
    func testAStatedZeroFeeTravelsAndKeepsItsCoinContext() throws {
        let payload = makeSwapKitPayload(
            swapFee: "0",
            swapFeeChain: Chain.bitcoinCash.name,
            swapFeeTokenId: nil,
            swapFeeDecimals: 8
        )
        guard case let .swapkitSwapPayload(value) = SwapPayload.swapkit(payload).mapToProtobuff() else {
            XCTFail("Expected .swapkitSwapPayload"); return
        }
        XCTAssertEqual(value.swapFee, "0")
        XCTAssertTrue(value.hasSwapFeeChain, "A zero still needs its coin to render as $0.00")
        XCTAssertTrue(value.hasSwapFeeDecimals)

        guard case let .swapkit(decoded) = try SwapPayload(proto: .swapkitSwapPayload(value)) else {
            XCTFail("Expected .swapkit"); return
        }
        XCTAssertEqual(decoded.swapFee, "0")
    }

    /// A stated zero renders a `$0.00` row, matching an initiator that itemizes
    /// one; only a genuinely absent fee hides it.
    func testResolverRendersAStatedZero() {
        let resolved = JoinKeysignSwapFeeViewModel().resolveSwapFee(
            swapPayload: .swapkit(makeSwapKitPayload(
                swapFee: "0",
                swapFeeChain: Chain.bitcoinCash.name,
                swapFeeTokenId: nil,
                swapFeeDecimals: 8
            )),
            vault: nil
        )
        XCTAssertEqual(resolved?.amount, 0)
        XCTAssertEqual(resolved?.coin.ticker, "BCH")
    }

    /// The generic path keeps hiding a zero: `EVMQuote.Transaction.swapFee`
    /// defaults to "0" when a quote omits the key, so a zero there cannot be
    /// told from "never quoted".
    func testGenericPathStillHidesAZero() {
        XCTAssertNil(JoinKeysignSwapFeeViewModel().resolveSwapFee(
            swapPayload: .generic(makeGenericPayload(swapFee: "0")),
            vault: nil
        ))
    }

    func testLegacyWireBytesDecodeToNoFeeAndNoRow() throws {
        let reparsed = try VSSwapKitSwapPayload(serializedBytes: try makeLegacyProto().serializedData())
        let decoded = try SwapPayload(proto: .swapkitSwapPayload(reparsed))

        guard case let .swapkit(payload) = decoded else {
            XCTFail("Expected .swapkit"); return
        }
        XCTAssertNil(payload.swapFee)
        XCTAssertNil(payload.swapFeeChain)
        XCTAssertNil(payload.swapFeeTokenId)
        XCTAssertNil(payload.swapFeeDecimals)
        XCTAssertNil(
            JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: decoded, vault: nil),
            "Legacy sender → render no row, never a definite $0.00"
        )
    }

    /// Byte-for-byte, not just "the fields are unset": a presence-only assertion
    /// would survive any other field shifting.
    func testReEncodingALegacyPayloadIsByteIdentical() throws {
        let originalBytes = try makeLegacyProto().serializedData()
        let decoded = try SwapPayload(proto: .swapkitSwapPayload(
            try VSSwapKitSwapPayload(serializedBytes: originalBytes)
        ))
        guard case let .swapkitSwapPayload(reEncoded) = decoded.mapToProtobuff() else {
            XCTFail("Expected .swapkitSwapPayload"); return
        }
        XCTAssertTrue(reEncoded.swapFee.isEmpty)
        XCTAssertFalse(reEncoded.hasSwapFeeChain)
        XCTAssertFalse(reEncoded.hasSwapFeeTokenID)
        XCTAssertFalse(reEncoded.hasSwapFeeDecimals)
        XCTAssertEqual(
            reEncoded, try VSSwapKitSwapPayload(serializedBytes: originalBytes),
            "Re-encoding must not add, drop or rewrite any field"
        )
        XCTAssertEqual(
            try reEncoded.serializedData(), originalBytes,
            "A relayed legacy payload must re-serialize to the sender's exact bytes"
        )
    }

    /// Compares the real BIP-143 pre-signing hashes — the bytes the vault commits
    /// to — with and without the fee group. A field-comparison test would pass
    /// even if a signer began folding a display field into what it signs.
    func testFeeGroupDoesNotMoveTheSignedPreSigningHashes() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self, from: "v3-real-btc-all-swap"
        )
        guard case let .psbt(base64) = response.tx else {
            XCTFail("Expected a PSBT fixture"); return
        }
        let psbt = try XCTUnwrap(Data(base64Encoded: base64))

        let withFee = makeSwapKitPayload(
            swapFee: "250000",
            swapFeeChain: Chain.bitcoinCash.name,
            swapFeeTokenId: nil,
            swapFeeDecimals: 8,
            txPayload: psbt
        )
        let withoutFee = makeSwapKitPayload(
            swapFee: nil, swapFeeChain: nil, swapFeeTokenId: nil, swapFeeDecimals: nil,
            txPayload: psbt
        )

        let signedWithFee = try SwapKitBTCSigner.preSigningHashes(payload: withFee)
        XCTAssertFalse(signedWithFee.isEmpty, "…or the comparison below is vacuous")
        XCTAssertEqual(
            signedWithFee,
            try SwapKitBTCSigner.preSigningHashes(payload: withoutFee),
            "A display field must never reach what the vault signs"
        )
    }

    /// Clearing the group must reproduce the bytes of a payload that never had
    /// it, so nothing else moved.
    func testFeeGroupIsPurelyAdditiveOnTheWire() throws {
        guard case var .swapkitSwapPayload(withFee) = SwapPayload.swapkit(makeSwapKitPayload(
                swapFee: "250000", swapFeeChain: Chain.bitcoinCash.name,
                swapFeeTokenId: nil, swapFeeDecimals: 8
              )).mapToProtobuff(),
              case let .swapkitSwapPayload(withoutFee) = SwapPayload.swapkit(makeSwapKitPayload(
                swapFee: nil, swapFeeChain: nil, swapFeeTokenId: nil, swapFeeDecimals: nil
              )).mapToProtobuff() else {
            XCTFail("Expected .swapkitSwapPayload"); return
        }
        XCTAssertNotEqual(try withFee.serializedData(), try withoutFee.serializedData())

        withFee.swapFee = ""
        withFee.clearSwapFeeChain()
        withFee.clearSwapFeeTokenID()
        withFee.clearSwapFeeDecimals()
        XCTAssertEqual(
            try withFee.serializedData(), try withoutFee.serializedData(),
            "The fee group must be the ONLY difference these bytes carry"
        )
    }

    // MARK: - What the co-signer reads back

    func testResolverAppliesWireDecimalsToANativeFee() {
        // 250_000 raw @ 8 decimals is 0.0025 BCH — the 50 bps affiliate charge a
        // NEAR route reports on a BCH source, in the source chain's own coin.
        let resolved = JoinKeysignSwapFeeViewModel().resolveSwapFee(
            swapPayload: .swapkit(makeSwapKitPayload(
                swapFee: "250000",
                swapFeeChain: Chain.bitcoinCash.name,
                swapFeeTokenId: nil,
                swapFeeDecimals: 8
            )),
            vault: nil
        )
        XCTAssertEqual(resolved?.amount, Decimal(string: "0.0025"))
        XCTAssertEqual(resolved?.coin.ticker, "BCH")
        XCTAssertTrue(resolved?.coin.isNativeToken ?? false)
    }

    func testResolverMatchesATokenFeeAgainstOneSideOfTheSwap() {
        let resolved = JoinKeysignSwapFeeViewModel().resolveSwapFee(
            swapPayload: .swapkit(makeSwapKitPayload(
                swapFee: "150000",
                swapFeeChain: "Ethereum",
                swapFeeTokenId: usdcContract.uppercased(),
                swapFeeDecimals: 6
            )),
            vault: nil
        )
        XCTAssertEqual(resolved?.amount, Decimal(string: "0.15"))
        XCTAssertEqual(resolved?.coin.ticker, "USDC", "Token id matches toCoin case-insensitively")
    }

    func testResolverYieldsNoRowWithoutCoinContext() {
        let model = JoinKeysignSwapFeeViewModel()
        // Missing chain, unknown chain, and missing decimals each make the coin
        // unknowable. A 6-decimal fee read as an 8-decimal one is wrong by 100x.
        XCTAssertNil(model.resolveSwapFee(swapPayload: .swapkit(makeSwapKitPayload(
            swapFee: "250000", swapFeeChain: nil, swapFeeTokenId: nil, swapFeeDecimals: 8
        )), vault: nil))
        XCTAssertNil(model.resolveSwapFee(swapPayload: .swapkit(makeSwapKitPayload(
            swapFee: "250000", swapFeeChain: "NotARealChain", swapFeeTokenId: nil, swapFeeDecimals: 8
        )), vault: nil))
        XCTAssertNil(model.resolveSwapFee(swapPayload: .swapkit(makeSwapKitPayload(
            swapFee: "250000", swapFeeChain: Chain.bitcoinCash.name, swapFeeTokenId: nil, swapFeeDecimals: nil
        )), vault: nil))
    }

    /// `swap_fee_decimals` is an `int32` the sender chooses, so the resolver must
    /// bound it before it reaches `pow(10, decimals)`. Unbounded, `-9` renders a
    /// fee 10^9x too large and anything past `Decimal`'s exponent range renders
    /// the literal string "NaN" — both on the screen the co-signer reads to
    /// decide whether to sign.
    func testResolverYieldsNoRowForOutOfRangeWireDecimals() {
        let model = JoinKeysignSwapFeeViewModel()
        for decimals in [-1, -9, 37, 130, Int(Int32.max)] {
            XCTAssertNil(
                model.resolveSwapFee(swapPayload: .swapkit(makeSwapKitPayload(
                    swapFee: "250000",
                    swapFeeChain: Chain.bitcoinCash.name,
                    swapFeeTokenId: nil,
                    swapFeeDecimals: decimals
                )), vault: nil),
                "decimals=\(decimals) is unusable, so no row beats a wrong one"
            )
            XCTAssertNil(
                model.resolveSwapFee(swapPayload: .generic(GenericSwapPayload(
                    fromCoin: makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true),
                    toCoin: makeUSDC(),
                    fromAmount: BigInt("1000000000000000000"),
                    toAmountDecimal: 3000,
                    quote: EVMQuote(
                        dstAmount: "3000000000",
                        tx: EVMQuote.Transaction(
                            from: "0xFrom", to: "0xRouter", data: "0x", value: "0",
                            gasPrice: "1", gas: 100_000,
                            swapFee: "5000000", swapFeeTokenContract: usdcContract
                        )
                    ),
                    provider: .oneInch,
                    swapFeeChain: "Ethereum",
                    swapFeeTokenId: usdcContract,
                    swapFeeDecimals: decimals
                )), vault: nil),
                "The generic path shares the resolver, so it shares the bound"
            )
        }
    }

    /// The bound is inclusive at both ends: `0` is a real integer-denominated
    /// fee and must still render.
    func testResolverAcceptsTheEdgesOfTheSupportedRange() {
        let model = JoinKeysignSwapFeeViewModel()
        XCTAssertEqual(
            model.resolveSwapFee(swapPayload: .swapkit(makeSwapKitPayload(
                swapFee: "250000", swapFeeChain: Chain.bitcoinCash.name,
                swapFeeTokenId: nil, swapFeeDecimals: 0
            )), vault: nil)?.amount,
            250_000
        )
        XCTAssertEqual(
            model.resolveSwapFee(swapPayload: .swapkit(makeSwapKitPayload(
                swapFee: "250000", swapFeeChain: Chain.bitcoinCash.name,
                swapFeeTokenId: nil, swapFeeDecimals: 36
            )), vault: nil)?.amount,
            Decimal(string: "0.00000000000000000000000000000025")
        )
    }

    func testResolverYieldsNoRowForAnUnknownTokenId() {
        XCTAssertNil(JoinKeysignSwapFeeViewModel().resolveSwapFee(
            swapPayload: .swapkit(makeSwapKitPayload(
                swapFee: "150000",
                swapFeeChain: "Ethereum",
                swapFeeTokenId: "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
                swapFeeDecimals: 6
            )),
            vault: nil
        ))
    }

    func testResolverYieldsNoRowForAnAbsentFee() {
        let model = JoinKeysignSwapFeeViewModel()
        for fee in [nil, ""] as [String?] {
            XCTAssertNil(
                model.resolveSwapFee(swapPayload: .swapkit(makeSwapKitPayload(
                    swapFee: fee, swapFeeChain: Chain.bitcoinCash.name, swapFeeTokenId: nil, swapFeeDecimals: 8
                )), vault: nil),
                "fee=\(String(describing: fee)) is unknown, not zero"
            )
        }
    }

    func testGenericRouteResolutionIsUnchangedByTheSharedPath() {
        let resolved = JoinKeysignSwapFeeViewModel().resolveSwapFee(
            swapPayload: .generic(GenericSwapPayload(
                fromCoin: makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true),
                toCoin: makeUSDC(),
                fromAmount: BigInt("1000000000000000000"),
                toAmountDecimal: 3000,
                quote: EVMQuote(
                    dstAmount: "3000000000",
                    tx: EVMQuote.Transaction(
                        from: "0xFrom", to: "0xRouter", data: "0x", value: "0",
                        gasPrice: "1", gas: 100_000,
                        swapFee: "5000000", swapFeeTokenContract: usdcContract
                    )
                ),
                provider: .oneInch,
                swapFeeChain: "Ethereum",
                swapFeeTokenId: usdcContract,
                swapFeeDecimals: 6
            )),
            vault: nil
        )
        XCTAssertEqual(resolved?.amount, 5)
        XCTAssertEqual(resolved?.coin.ticker, "USDC")
    }

    // MARK: - Persisted JSON back-compat

    func testSwapKitPayloadJSONWithoutFeeKeysDecodes() throws {
        let encoded = try JSONEncoder().encode(makeSwapKitPayload(
            swapFee: nil, swapFeeChain: nil, swapFeeTokenId: nil, swapFeeDecimals: nil
        ))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        for key in ["swapFee", "swapFeeChain", "swapFeeTokenId", "swapFeeDecimals"] {
            object.removeValue(forKey: key)
        }
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(SwapKitSwapPayload.self, from: stripped)
        XCTAssertNil(decoded.swapFee)
        XCTAssertNil(decoded.swapFeeChain)
        XCTAssertNil(decoded.swapFeeTokenId)
        XCTAssertNil(decoded.swapFeeDecimals)
        XCTAssertEqual(decoded.txType, "PSBT", "The pre-existing fields still decode")
    }

    // MARK: - Fixtures

    private let usdcContract = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"

    private func makeGenericPayload(swapFee: String) -> GenericSwapPayload {
        GenericSwapPayload(
            fromCoin: makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true),
            toCoin: makeUSDC(),
            fromAmount: BigInt("1000000000000000000"),
            toAmountDecimal: 3000,
            quote: EVMQuote(
                dstAmount: "3000000000",
                tx: EVMQuote.Transaction(
                    from: "0xFrom", to: "0xRouter", data: "0x", value: "0",
                    gasPrice: "1", gas: 100_000,
                    swapFee: swapFee, swapFeeTokenContract: usdcContract
                )
            ),
            provider: .oneInch,
            swapFeeChain: "Ethereum",
            swapFeeTokenId: usdcContract,
            swapFeeDecimals: 6
        )
    }

    private func makeSwapKitPayload(
        swapFee: String?,
        swapFeeChain: String?,
        swapFeeTokenId: String?,
        swapFeeDecimals: Int?,
        txPayload: Data = Data([0x70, 0x73, 0x62, 0x74])
    ) -> SwapKitSwapPayload {
        SwapKitSwapPayload(
            fromCoin: makeCoin(.bitcoinCash, ticker: "BCH", decimals: 8, isNative: true),
            toCoin: makeUSDC(),
            fromAmount: BigInt(50_000_000),
            toAmountDecimal: 380,
            txType: "PSBT",
            txPayload: txPayload,
            targetAddress: "qtarget",
            inboundAddress: nil,
            memo: nil,
            subProvider: "NEAR",
            swapID: "swap-1",
            swapFee: swapFee,
            swapFeeChain: swapFeeChain,
            swapFeeTokenId: swapFeeTokenId,
            swapFeeDecimals: swapFeeDecimals
        )
    }

    /// Fields 1-11 only — the shape a sender predating fields 12-15 sends.
    private func makeLegacyProto() -> VSSwapKitSwapPayload {
        var legacy = VSSwapKitSwapPayload()
        legacy.fromCoin = ProtoCoinResolver.proto(from: makeCoin(.bitcoinCash, ticker: "BCH", decimals: 8, isNative: true))
        legacy.toCoin = ProtoCoinResolver.proto(from: makeUSDC())
        legacy.fromAmount = "50000000"
        legacy.toAmountDecimal = "380"
        legacy.txType = "PSBT"
        legacy.txPayload = Data([0x70, 0x73, 0x62, 0x74])
        legacy.targetAddress = "qtarget"
        legacy.subProvider = "NEAR"
        legacy.swapID = "swap-1"
        return legacy
    }

    private func makeUSDC() -> Coin {
        makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, contract: usdcContract)
    }

    private func makeCoin(
        _ chain: Chain,
        ticker: String,
        decimals: Int,
        isNative: Bool,
        contract: String = ""
    ) -> Coin {
        let asset = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "logo",
            decimals: decimals,
            priceProviderId: "swapkit-fee-5341-\(ticker.lowercased())",
            contractAddress: contract,
            isNativeToken: isNative
        )
        return Coin(asset: asset, address: "swapkit-fee-\(ticker)", hexPublicKey: "")
    }
}
