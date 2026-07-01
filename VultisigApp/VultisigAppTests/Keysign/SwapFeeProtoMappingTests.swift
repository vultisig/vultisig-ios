//
//  SwapFeeProtoMappingTests.swift
//  VultisigAppTests
//
//  Coverage for the swap-fee coin context on `OneInchTransaction`
//  (swap_fee_chain / swap_fee_token_id / swap_fee_decimals): proto
//  round-trips with explicit presence, raw pre-context wire bytes,
//  the co-signer display resolver's never-guess semantics, and
//  persisted-JSON back-compat for `GenericSwapPayload`.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SwapFeeProtoMappingTests: XCTestCase {

    // MARK: - Proto round-trip

    func testProtoRoundTripCarriesSwapFeeCoinContext() throws {
        let payload = makeGenericPayload(
            swapFee: "5000000",
            swapFeeChain: "Ethereum",
            swapFeeTokenId: usdcContract,
            swapFeeDecimals: 6
        )

        let proto = SwapPayload.generic(payload).mapToProtobuff()
        guard case let .oneinchSwapPayload(value) = proto else {
            XCTFail("Expected .oneinchSwapPayload"); return
        }
        XCTAssertTrue(value.quote.tx.hasSwapFeeChain)
        XCTAssertTrue(value.quote.tx.hasSwapFeeTokenID)
        XCTAssertTrue(value.quote.tx.hasSwapFeeDecimals)
        XCTAssertEqual(value.quote.tx.swapFeeChain, "Ethereum")
        XCTAssertEqual(value.quote.tx.swapFeeTokenID, usdcContract)
        XCTAssertEqual(value.quote.tx.swapFeeDecimals, 6)

        let decoded = try SwapPayload(proto: proto)
        guard case let .generic(decodedPayload) = decoded else {
            XCTFail("Expected .generic"); return
        }
        XCTAssertEqual(decodedPayload.swapFeeChain, "Ethereum")
        XCTAssertEqual(decodedPayload.swapFeeTokenId, usdcContract)
        XCTAssertEqual(decodedPayload.swapFeeDecimals, 6)
        XCTAssertEqual(decodedPayload.quote.tx.swapFee, "5000000")
        XCTAssertEqual(
            decodedPayload.quote.tx.swapFeeTokenContract, usdcContract,
            "Decoded quote should be self-consistent with the wire token id"
        )
    }

    func testProtoRoundTripWithoutContextLeavesFieldsAbsent() throws {
        let payload = makeGenericPayload(
            swapFee: "5000000",
            swapFeeChain: nil,
            swapFeeTokenId: nil,
            swapFeeDecimals: nil
        )

        let proto = SwapPayload.generic(payload).mapToProtobuff()
        guard case let .oneinchSwapPayload(value) = proto else {
            XCTFail("Expected .oneinchSwapPayload"); return
        }
        XCTAssertFalse(value.quote.tx.hasSwapFeeChain, "nil context must be absent, not present-empty")
        XCTAssertFalse(value.quote.tx.hasSwapFeeTokenID)
        XCTAssertFalse(value.quote.tx.hasSwapFeeDecimals)

        let decoded = try SwapPayload(proto: proto)
        guard case let .generic(decodedPayload) = decoded else {
            XCTFail("Expected .generic"); return
        }
        XCTAssertNil(decodedPayload.swapFeeChain)
        XCTAssertNil(decodedPayload.swapFeeTokenId)
        XCTAssertNil(decodedPayload.swapFeeDecimals)
    }

    func testZeroSwapFeeSetsNeitherFeeNorContextOnProto() {
        let payload = makeGenericPayload(
            swapFee: "0",
            swapFeeChain: "Ethereum",
            swapFeeTokenId: usdcContract,
            swapFeeDecimals: 6
        )

        let proto = SwapPayload.generic(payload).mapToProtobuff()
        guard case let .oneinchSwapPayload(value) = proto else {
            XCTFail("Expected .oneinchSwapPayload"); return
        }
        XCTAssertEqual(value.quote.tx.swapFee, "", "Zero fee stays off the wire")
        XCTAssertFalse(value.quote.tx.hasSwapFeeChain)
        XCTAssertFalse(value.quote.tx.hasSwapFeeTokenID)
        XCTAssertFalse(value.quote.tx.hasSwapFeeDecimals)
    }

    // MARK: - Jupiter provider round-trip

    func testJupiterProviderRoundTripsThroughProto() throws {
        let payload = GenericSwapPayload(
            fromCoin: makeCoin(.solana, ticker: "SOL", decimals: 9, isNative: true),
            toCoin: makeCoin(
                .solana, ticker: "USDC", decimals: 6, isNative: false,
                contract: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"
            ),
            fromAmount: BigInt("1000000000"),
            toAmountDecimal: 25,
            quote: EVMQuote(
                dstAmount: "25000000",
                tx: EVMQuote.Transaction(
                    from: "SoLfrom",
                    to: "SoLmint",
                    data: "AQIDBA==",
                    value: "0",
                    gasPrice: "0",
                    gas: 0
                )
            ),
            provider: .jupiter
        )

        let proto = SwapPayload.generic(payload).mapToProtobuff()
        guard case let .oneinchSwapPayload(value) = proto else {
            XCTFail("Expected .oneinchSwapPayload"); return
        }
        XCTAssertEqual(value.provider, "jupiter", "Jupiter serializes as the 'jupiter' wire string")

        let decoded = try SwapPayload(proto: proto)
        guard case let .generic(decodedPayload) = decoded else {
            XCTFail("Expected .generic"); return
        }
        XCTAssertEqual(decodedPayload.provider, .jupiter, "Tolerant decode maps 'jupiter' back to .jupiter")
        XCTAssertEqual(
            decodedPayload.quote.tx.data, "AQIDBA==",
            "Base64 Solana wire tx survives the proto round-trip (co-signer signs the same bytes)"
        )
    }

    // MARK: - Pre-context wire bytes

    func testPreContextWireBytesDecodeWithNilContextAndNoFeeRow() throws {
        // A sender that predates the schema extension serializes only
        // fields 1-7 on the transaction.
        var legacyProto = VSOneInchSwapPayload()
        legacyProto.fromCoin = ProtoCoinResolver.proto(from: makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true))
        legacyProto.toCoin = ProtoCoinResolver.proto(from: makeUSDC())
        legacyProto.fromAmount = "1000000000000000000"
        legacyProto.toAmountDecimal = "3000"
        legacyProto.quote = .with {
            $0.dstAmount = "3000000000"
            $0.tx = .with {
                $0.from = "0xFrom"
                $0.to = "0xRouter"
                $0.data = "0x"
                $0.value = "0"
                $0.gasPrice = "1"
                $0.gas = 100_000
                $0.swapFee = "5000000"
            }
        }
        legacyProto.provider = "1inch"

        let bytes = try legacyProto.serializedData()
        let reparsed = try VSOneInchSwapPayload(serializedBytes: bytes)
        let decoded = try SwapPayload(proto: .oneinchSwapPayload(reparsed))

        guard case let .generic(payload) = decoded else {
            XCTFail("Expected .generic"); return
        }
        XCTAssertEqual(payload.quote.tx.swapFee, "5000000")
        XCTAssertNil(payload.swapFeeChain)
        XCTAssertNil(payload.swapFeeTokenId)
        XCTAssertNil(payload.swapFeeDecimals)

        let resolved = JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: decoded, vault: nil)
        XCTAssertNil(resolved, "Pre-context sender → never guess a coin, render no row")
    }

    // MARK: - Display resolver

    func testResolverMatchesToCoinAndAppliesWireDecimals() {
        // 5_000_000 raw @ 6 decimals is 5.0 USDC — not 5e-12 (the failure
        // mode of reading a destination-token fee with native 18 decimals).
        let payload = makeGenericPayload(
            swapFee: "5000000",
            swapFeeChain: "Ethereum",
            swapFeeTokenId: usdcContract.uppercased(),
            swapFeeDecimals: 6
        )

        let resolved = JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: .generic(payload), vault: nil)

        XCTAssertEqual(resolved?.amount, 5)
        XCTAssertEqual(resolved?.coin.ticker, "USDC", "Token id matches toCoin case-insensitively")
    }

    func testResolverWireDecimalsWinOverResolvedCoinDecimals() {
        // toCoin says 6 decimals but the wire declares 18 — the sender
        // serialized the raw amount in wire units, so wire wins.
        let payload = makeGenericPayload(
            swapFee: "1000000000000000000",
            swapFeeChain: "Ethereum",
            swapFeeTokenId: usdcContract,
            swapFeeDecimals: 18
        )

        let resolved = JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: .generic(payload), vault: nil)

        XCTAssertEqual(resolved?.amount, 1)
    }

    func testResolverNilTokenIdFallsBackToVaultNativeCoin() {
        let vault = Vault(name: "Test Vault")
        vault.coins.append(makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true))
        let payload = makeGenericPayload(
            swapFee: "10000000000000000",
            swapFeeChain: "Ethereum",
            swapFeeTokenId: nil,
            swapFeeDecimals: 18
        )

        let resolved = JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: .generic(payload), vault: vault)

        XCTAssertEqual(resolved?.amount, Decimal(string: "0.01"))
        XCTAssertEqual(resolved?.coin.ticker, "ETH")
        XCTAssertTrue(resolved?.coin.isNativeToken ?? false)
    }

    func testResolverNilTokenIdWithoutVaultUsesTokensStoreNative() {
        let payload = makeGenericPayload(
            swapFee: "10000000000000000",
            swapFeeChain: "Ethereum",
            swapFeeTokenId: nil,
            swapFeeDecimals: 18
        )

        let resolved = JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: .generic(payload), vault: nil)

        XCTAssertEqual(resolved?.coin.ticker, "ETH")
        XCTAssertTrue(resolved?.coin.isNativeToken ?? false)
    }

    func testResolverUnknownChainYieldsNoRow() {
        let payload = makeGenericPayload(
            swapFee: "5000000",
            swapFeeChain: "NotARealChain",
            swapFeeTokenId: usdcContract,
            swapFeeDecimals: 6
        )

        XCTAssertNil(JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: .generic(payload), vault: nil))
    }

    func testResolverUnknownTokenIdYieldsNoRow() {
        let payload = makeGenericPayload(
            swapFee: "5000000",
            swapFeeChain: "Ethereum",
            swapFeeTokenId: "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef",
            swapFeeDecimals: 6
        )

        XCTAssertNil(JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: .generic(payload), vault: nil))
    }

    func testResolverMissingDecimalsYieldsNoRow() {
        let payload = makeGenericPayload(
            swapFee: "5000000",
            swapFeeChain: "Ethereum",
            swapFeeTokenId: usdcContract,
            swapFeeDecimals: nil
        )

        XCTAssertNil(JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: .generic(payload), vault: nil))
    }

    func testResolverZeroFeeYieldsNoRow() {
        let payload = makeGenericPayload(
            swapFee: "0",
            swapFeeChain: "Ethereum",
            swapFeeTokenId: usdcContract,
            swapFeeDecimals: 6
        )

        XCTAssertNil(JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: .generic(payload), vault: nil))
    }

    func testGetSwapFeeWithRateProducesFiatValue() {
        let payload = makeGenericPayload(
            swapFee: "5000000",
            swapFeeChain: "Ethereum",
            swapFeeTokenId: usdcContract,
            swapFeeDecimals: 6
        )
        let cryptoId = RateProvider.cryptoId(for: makeUSDC().toCoinMeta()).id
        // In-memory rates update before the storage write, so a storage
        // failure in the test harness doesn't invalidate the assertion.
        try? RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: cryptoId, value: 1.0)
        ])

        let fees = JoinKeysignSwapFeeViewModel().getSwapFee(swapPayload: .generic(payload), vault: nil)

        XCTAssertNotNil(fees)
        XCTAssertTrue(fees?.feeCrypto.contains("USDC") ?? false)
        XCTAssertFalse(fees?.feeFiat.isEmpty ?? true, "Seeded rate should produce a fiat string")
    }

    // MARK: - Persisted-JSON back-compat

    func testGenericSwapPayloadJSONWithoutContextKeysDecodes() throws {
        // A payload persisted before the context fields existed encodes the
        // same JSON as one with nil context today (optionals are omitted).
        let legacy = makeGenericPayload(
            swapFee: "5000000",
            swapFeeChain: nil,
            swapFeeTokenId: nil,
            swapFeeDecimals: nil
        )
        let data = try JSONEncoder().encode(legacy)
        let json = try XCTUnwrap(String(bytes: data, encoding: .utf8))
        XCTAssertFalse(json.contains("swapFeeChain"), "nil optionals must be omitted from persisted JSON")

        let decoded = try JSONDecoder().decode(GenericSwapPayload.self, from: data)
        XCTAssertNil(decoded.swapFeeChain)
        XCTAssertNil(decoded.swapFeeTokenId)
        XCTAssertNil(decoded.swapFeeDecimals)
        XCTAssertEqual(decoded.quote.tx.swapFee, "5000000")
    }

    func testGenericSwapPayloadJSONRoundTripsContext() throws {
        let payload = makeGenericPayload(
            swapFee: "5000000",
            swapFeeChain: "Ethereum",
            swapFeeTokenId: usdcContract,
            swapFeeDecimals: 6
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(GenericSwapPayload.self, from: data)
        XCTAssertEqual(decoded.swapFeeChain, "Ethereum")
        XCTAssertEqual(decoded.swapFeeTokenId, usdcContract)
        XCTAssertEqual(decoded.swapFeeDecimals, 6)
    }

    // MARK: - Fixtures

    private let usdcContract = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"

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
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }

    private func makeUSDC() -> Coin {
        makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, contract: usdcContract)
    }

    private func makeGenericPayload(
        swapFee: String,
        swapFeeChain: String?,
        swapFeeTokenId: String?,
        swapFeeDecimals: Int?
    ) -> GenericSwapPayload {
        GenericSwapPayload(
            fromCoin: makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true),
            toCoin: makeUSDC(),
            fromAmount: BigInt("1000000000000000000"),
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
                    swapFee: swapFee,
                    swapFeeTokenContract: swapFeeTokenId ?? ""
                )
            ),
            provider: .oneInch,
            swapFeeChain: swapFeeChain,
            swapFeeTokenId: swapFeeTokenId,
            swapFeeDecimals: swapFeeDecimals
        )
    }
}
