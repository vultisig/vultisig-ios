//
//  SwapKitSwapFeeProtoMappingTests.swift
//  VultisigAppTests
//
//  Coverage for the provider fee on `SwapKitSwapPayload` (swap_fee plus the
//  chain / token id / decimals that say what coin it is denominated in). A
//  co-signer holds no quote, so a fee that does not travel on the payload is a
//  fee it can neither recover nor show — its confirm screen would total the
//  network fee alone. These pin the wire shape, the never-guess resolution, and
//  that an absent field keeps reading as "unknown" rather than zero.
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

    func testZeroFeeStaysOffTheWire() {
        let payload = makeSwapKitPayload(
            swapFee: "0",
            swapFeeChain: Chain.bitcoinCash.name,
            swapFeeTokenId: nil,
            swapFeeDecimals: 8
        )
        guard case let .swapkitSwapPayload(value) = SwapPayload.swapkit(payload).mapToProtobuff() else {
            XCTFail("Expected .swapkitSwapPayload"); return
        }
        XCTAssertTrue(
            value.swapFee.isEmpty,
            "A zero is indistinguishable from unknown here; never claim it"
        )
        XCTAssertFalse(value.hasSwapFeeChain)
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

    /// Byte-for-byte, not just "the fields are unset" — mixed-version MPC
    /// committees depend on a relayed legacy payload re-serializing identically,
    /// and a presence-only assertion would survive any other field shifting.
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

    /// The strongest form of the display-only claim available here: run the real
    /// BTC PSBT signer over a payload carrying the fee group and one without it,
    /// and compare the actual BIP-143 pre-signing hashes — the bytes the vault
    /// commits to. A field-comparison test would pass even if a signer began
    /// folding a display field into what it signs; this one would not.
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

    /// Wire-level counterpart: clearing the group from a payload that carries it
    /// must reproduce the bytes of one that never had it, so nothing else moved.
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

    func testResolverYieldsNoRowForZeroOrAbsentFee() {
        let model = JoinKeysignSwapFeeViewModel()
        for fee in [nil, "", "0"] as [String?] {
            XCTAssertNil(
                model.resolveSwapFee(swapPayload: .swapkit(makeSwapKitPayload(
                    swapFee: fee, swapFeeChain: Chain.bitcoinCash.name, swapFeeTokenId: nil, swapFeeDecimals: 8
                )), vault: nil),
                "fee=\(String(describing: fee)) must render no row"
            )
        }
    }

    func testGenericRouteResolutionIsUnchangedByTheSharedPath() {
        // The generic and SwapKit resolvers now share one implementation; this
        // pins that the 1inch-shaped route still resolves exactly as before.
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

    /// Fields 1-11 only — the shape a sender predating fields 12-15 puts on the
    /// wire.
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
