//
//  SwapSubProviderProtoMappingTests.swift
//  VultisigAppTests
//
//  Coverage for `OneInchSwapPayload.sub_provider` — the route tag under an
//  aggregator ("NEAR", "CHAINFLIP", "GARDEN"), which SwapKit's EVM and Solana
//  routes carry on the 1inch-shaped payload.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SwapSubProviderProtoMappingTests: XCTestCase {

    // MARK: - Proto round-trip

    func testProtoRoundTripCarriesSubProvider() throws {
        let proto = SwapPayload.generic(makeGenericPayload(subProvider: "NEAR")).mapToProtobuff()
        guard case let .oneinchSwapPayload(value) = proto else {
            XCTFail("Expected .oneinchSwapPayload"); return
        }
        XCTAssertEqual(value.subProvider, "NEAR")

        guard case let .generic(decoded) = try SwapPayload(proto: proto) else {
            XCTFail("Expected .generic"); return
        }
        XCTAssertEqual(decoded.subProvider, "NEAR")
    }

    func testNilAndEmptySubProviderStayOffTheWire() throws {
        for subProvider in [nil, ""] as [String?] {
            let proto = SwapPayload.generic(makeGenericPayload(subProvider: subProvider)).mapToProtobuff()
            guard case let .oneinchSwapPayload(value) = proto else {
                XCTFail("Expected .oneinchSwapPayload"); return
            }
            XCTAssertTrue(
                value.subProvider.isEmpty,
                "An absent tag stays at the field default rather than being written empty"
            )

            guard case let .generic(decoded) = try SwapPayload(proto: proto) else {
                XCTFail("Expected .generic"); return
            }
            XCTAssertNil(decoded.subProvider, "Empty on the wire normalizes back to nil, not \"\"")
        }
    }

    func testLegacyWireBytesDecodeToNoTagAndTheBareBrand() throws {
        let reparsed = try VSOneInchSwapPayload(serializedBytes: try makeLegacyProto().serializedData())
        let decoded = try SwapPayload(proto: .oneinchSwapPayload(reparsed))

        guard case let .generic(payload) = decoded else {
            XCTFail("Expected .generic"); return
        }
        XCTAssertNil(payload.subProvider)
        XCTAssertEqual(
            decoded.providerDisplayName, "SwapKit",
            "A sender predating the field named no route; do not invent one"
        )
    }

    /// Byte-for-byte, not just "the field is unset": a presence-only assertion
    /// would survive any other field shifting.
    func testReEncodingALegacyPayloadIsByteIdentical() throws {
        let originalBytes = try makeLegacyProto().serializedData()
        let decoded = try SwapPayload(proto: .oneinchSwapPayload(
            try VSOneInchSwapPayload(serializedBytes: originalBytes)
        ))
        guard case let .oneinchSwapPayload(reEncoded) = decoded.mapToProtobuff() else {
            XCTFail("Expected .oneinchSwapPayload"); return
        }
        XCTAssertTrue(
            reEncoded.subProvider.isEmpty,
            "Relaying a legacy payload must not invent a route its sender never stated"
        )
        XCTAssertEqual(
            reEncoded, try VSOneInchSwapPayload(serializedBytes: originalBytes),
            "Re-encoding must not add, drop or rewrite any field"
        )
        XCTAssertEqual(
            try reEncoded.serializedData(), originalBytes,
            "A relayed legacy payload must re-serialize to the sender's exact bytes"
        )
    }

    // MARK: - How the co-signer names the route

    /// The tag travels but this device does not render it: iOS's initiator screen
    /// names the clean brand, so rendering it here alone would describe one swap
    /// two ways.
    func testGenericRouteCarriesTheTagWithoutRenderingIt() {
        let payload = makeGenericPayload(subProvider: "NEAR")
        XCTAssertEqual(payload.subProvider, "NEAR", "…or the wire assertion below is vacuous")
        XCTAssertEqual(SwapPayload.generic(payload).providerDisplayName, "SwapKit")
        XCTAssertEqual(
            SwapPayload.generic(makeGenericPayload(subProvider: "CHAINFLIP", provider: .oneInch)).providerDisplayName,
            "1Inch"
        )
    }

    /// `providerName` is persisted and aliased back to a tracker by an exact
    /// lookup, so a tagged row would silently lose the SwapKit tracker link.
    func testPersistedProviderNameStaysTheBareBrand() {
        XCTAssertEqual(
            SwapPayload.generic(makeGenericPayload(subProvider: "NEAR")).providerName,
            "SwapKit"
        )
        let url = ExplorerLinkBuilder.url(
            provider: SwapPayload.generic(makeGenericPayload(subProvider: "NEAR")).providerName,
            txHash: "0xabc",
            chainRawValue: Chain.ethereum.rawValue,
            fallbackExplorerLink: "https://etherscan.io/tx/0xfallback"
        )
        XCTAssertEqual(
            url?.absoluteString, "https://track.swapkit.dev/?hash=0xabc&chainId=1",
            "The persisted identity still resolves to the aggregator's own tracker"
        )
    }

    /// SwapKit's own name is the fallback when a route reports no providers, so
    /// the tag can repeat the aggregator. "SwapKit (SwapKit)" names nothing.
    func testProviderDisplayNameDropsATagThatRepeatsTheAggregator() {
        XCTAssertEqual(
            SwapPayload.swapkit(makeSwapKitPayload(subProvider: "SwapKit")).providerDisplayName,
            "SwapKit"
        )
        XCTAssertEqual(
            SwapPayload.swapkit(makeSwapKitPayload(subProvider: "swapkit")).providerDisplayName,
            "SwapKit"
        )
    }

    /// The transfer-route half of the split: "SwapKit (CHAINFLIP)" normalizes to
    /// `swapkitchainflip`, which matches no alias, so a tagged persisted name
    /// falls back to the chain explorer.
    func testSwapKitTransferRoutePersistsTheBareBrandAndKeepsItsTracker() {
        let payload = SwapPayload.swapkit(makeSwapKitPayload(subProvider: "CHAINFLIP"))
        XCTAssertEqual(payload.providerName, "SwapKit")
        XCTAssertEqual(
            payload.providerDisplayName, "SwapKit (CHAINFLIP)",
            "The verify screen still names the route; only the persisted identity is bare"
        )
        XCTAssertEqual(
            ExplorerLinkBuilder.url(
                provider: payload.providerName,
                txHash: "0xabc",
                chainRawValue: Chain.ethereum.rawValue,
                fallbackExplorerLink: "https://etherscan.io/tx/0xfallback"
            )?.absoluteString,
            "https://track.swapkit.dev/?hash=0xabc&chainId=1"
        )
    }

    /// Pinned as the thing that must not come back. `url` only reaches
    /// `fallbackExplorerLink` when the CHAIN is unrecognised, so an unresolved
    /// provider falls through to the chain's registry explorer.
    func testATaggedPersistedNameWouldLoseTheTracker() {
        let url = ExplorerLinkBuilder.url(
            provider: "SwapKit (CHAINFLIP)",
            txHash: "0xabc",
            chainRawValue: Chain.ethereum.rawValue,
            fallbackExplorerLink: "https://etherscan.io/tx/0xfallback"
        )
        XCTAssertEqual(
            url?.absoluteString,
            ExplorerLinkBuilder.getExplorerURL(chain: .ethereum, txid: "0xabc"),
            "A tagged name resolves to no tracker and drops to the chain explorer"
        )
        XCTAssertNotEqual(
            url?.absoluteString, "https://track.swapkit.dev/?hash=0xabc&chainId=1",
            "…which is exactly the link the split exists to keep"
        )
    }

    func testTransferRouteNamingIsUnchanged() {
        XCTAssertEqual(
            SwapPayload.swapkit(makeSwapKitPayload(subProvider: "CHAINFLIP")).providerDisplayName,
            "SwapKit (CHAINFLIP)"
        )
        XCTAssertEqual(
            SwapPayload.swapkit(makeSwapKitPayload(subProvider: "")).providerDisplayName,
            "SwapKit"
        )
    }

    // MARK: - What the builder puts on the wire

    func testEvmSwapKitRouteCarriesTheRouteTag() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-erc20-erc20-swap"
        )
        let payload = SwapCryptoLogic.buildSwapKitGenericPayload(
            fromCoin: makeCoin(.ethereum, ticker: "USDT", decimals: 6, isNative: false),
            toCoin: makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false),
            fromAmountInCoin: BigInt(100_000_000),
            toAmountDecimal: 100,
            quote: try SwapCryptoLogic.buildEVMQuoteFromSwapKit(swapResponse: response),
            swapResponse: response
        )

        XCTAssertEqual(payload.subProvider, "ONEINCH")
        guard case let .oneinchSwapPayload(proto) = SwapPayload.generic(payload).mapToProtobuff() else {
            XCTFail("Expected .oneinchSwapPayload"); return
        }
        XCTAssertEqual(proto.subProvider, "ONEINCH", "The tag has to reach the peer")

        XCTAssertEqual(
            SwapPayload.generic(payload).providerDisplayName,
            SwapQuote.swapkit(response, fee: nil, subProvider: response.subProvider).displayName
        )
    }

    func testSolanaSwapKitRouteCarriesTheRouteTag() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-sol-near-swap-fresh"
        )
        let payload = SwapCryptoLogic.buildSwapKitGenericPayload(
            fromCoin: makeCoin(.solana, ticker: "SOL", decimals: 9, isNative: true),
            toCoin: makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false),
            fromAmountInCoin: BigInt(1_000_000_000),
            toAmountDecimal: 100,
            quote: try SwapCryptoLogic.buildEVMQuoteFromSwapKit(swapResponse: response),
            swapResponse: response
        )

        XCTAssertEqual(payload.subProvider, response.subProvider)
        XCTAssertEqual(payload.subProvider, "NEAR", "…or the parity assertion below is vacuous")
        XCTAssertEqual(
            SwapPayload.generic(payload).providerDisplayName,
            SwapQuote.swapkit(response, fee: nil, subProvider: response.subProvider).displayName,
            "Joiner and initiator must name this swap identically"
        )
    }

    /// A tag is a label. It must not disturb the calldata this device signs.
    func testTheRouteTagDoesNotTouchTheSignedQuote() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitSwapResponse.self,
            from: "v3-erc20-erc20-swap"
        )
        let quote = try SwapCryptoLogic.buildEVMQuoteFromSwapKit(swapResponse: response)
        let payload = SwapCryptoLogic.buildSwapKitGenericPayload(
            fromCoin: makeCoin(.ethereum, ticker: "USDT", decimals: 6, isNative: false),
            toCoin: makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false),
            fromAmountInCoin: BigInt(100_000_000),
            toAmountDecimal: 100,
            quote: quote,
            swapResponse: response
        )
        XCTAssertEqual(payload.quote, quote)
    }

    // MARK: - Persisted JSON back-compat

    func testGenericSwapPayloadJSONWithoutSubProviderDecodes() throws {
        let encoded = try JSONEncoder().encode(makeGenericPayload(subProvider: nil))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "subProvider")
        let stripped = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(GenericSwapPayload.self, from: stripped)
        XCTAssertNil(decoded.subProvider)
    }

    // MARK: - Fixtures

    private func makeGenericPayload(
        subProvider: String?,
        provider: SwapProviderId = .swapkit
    ) -> GenericSwapPayload {
        GenericSwapPayload(
            fromCoin: makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true),
            toCoin: makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false),
            fromAmount: BigInt("1000000000000000000"),
            toAmountDecimal: 3000,
            quote: EVMQuote(
                dstAmount: "3000000000",
                tx: EVMQuote.Transaction(
                    from: "0xFrom", to: "0xRouter", data: "0x", value: "0",
                    gasPrice: "1", gas: 100_000
                )
            ),
            provider: provider,
            subProvider: subProvider
        )
    }

    private func makeSwapKitPayload(subProvider: String) -> SwapKitSwapPayload {
        SwapKitSwapPayload(
            fromCoin: makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true),
            toCoin: makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false),
            fromAmount: BigInt(500_000),
            toAmountDecimal: 380,
            txType: "PSBT",
            txPayload: Data(),
            targetAddress: "bc1qtarget",
            inboundAddress: nil,
            memo: nil,
            subProvider: subProvider,
            swapID: "swap-1"
        )
    }

    /// Fields 1-6 only — the shape a sender predating field 7 sends.
    private func makeLegacyProto() -> VSOneInchSwapPayload {
        var legacy = VSOneInchSwapPayload()
        legacy.fromCoin = ProtoCoinResolver.proto(from: makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true))
        legacy.toCoin = ProtoCoinResolver.proto(from: makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false))
        legacy.fromAmount = "1000000000000000000"
        legacy.toAmountDecimal = "3000"
        legacy.provider = SwapProviderId.swapkit.rawValue
        legacy.quote = .with {
            $0.dstAmount = "3000000000"
            $0.tx = .with {
                $0.from = "0xFrom"
                $0.to = "0xRouter"
                $0.data = "0x"
                $0.value = "0"
                $0.gasPrice = "1"
                $0.gas = 100_000
            }
        }
        return legacy
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool) -> Coin {
        let asset = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "logo",
            decimals: decimals,
            priceProviderId: "sub-provider-5341-\(ticker.lowercased())",
            contractAddress: isNative ? "" : "0xcontract-\(ticker.lowercased())",
            isNativeToken: isNative
        )
        return Coin(asset: asset, address: "sub-provider-\(ticker)", hexPublicKey: "")
    }
}
