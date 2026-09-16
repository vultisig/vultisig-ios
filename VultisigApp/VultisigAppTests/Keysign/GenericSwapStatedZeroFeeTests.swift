//
//  GenericSwapStatedZeroFeeTests.swift
//  VultisigAppTests
//
//  `EVMQuote.Transaction.swapFee` carries three states: absent (nil, nothing
//  on the wire, no row anywhere), a stated zero ("0" plus coin context, a
//  $0.00 row on both devices) and a stated amount. These tests pin the model
//  and the readers that turn it into the co-signer's fee row.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class GenericSwapStatedZeroFeeTests: XCTestCase {

    // MARK: - Model

    func testMemberwiseInitDefaultsToAbsent() {
        let tx = EVMQuote.Transaction(from: "0xFrom", to: "0xTo", data: "0x", value: "0", gasPrice: "1", gas: 1)
        XCTAssertNil(tx.swapFee)
        XCTAssertEqual(tx.swapFeeTokenContract, "")
    }

    func testJSONWithoutSwapFeeDecodesToAbsent() throws {
        let quote = try decodeQuote(txJSON: baseTxJSON)
        XCTAssertNil(quote.tx.swapFee)
    }

    func testJSONWithZeroSwapFeeDecodesToStatedZero() throws {
        let quote = try decodeQuote(txJSON: baseTxJSON + #", "swapFee": "0""#)
        XCTAssertEqual(quote.tx.swapFee, "0")
    }

    func testJSONRoundTripKeepsAbsentAbsent() throws {
        let quote = EVMQuote(
            dstAmount: "1",
            tx: EVMQuote.Transaction(from: "0xFrom", to: "0xTo", data: "0x", value: "0", gasPrice: "1", gas: 1)
        )
        let data = try JSONEncoder().encode(quote)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("swapFee\""), "nil must be omitted, not encoded as null or \"0\"")
        XCTAssertNil(try JSONDecoder().decode(EVMQuote.self, from: data).tx.swapFee)
    }

    // MARK: - Readers

    func testEvmSwapFeeBigIntDistinguishesStatedZeroFromAbsent() {
        XCTAssertEqual(SwapQuote.kyberswap(makeQuote(swapFee: "0"), fee: nil).evmSwapFeeBigInt, 0)
        XCTAssertNil(SwapQuote.kyberswap(makeQuote(swapFee: nil), fee: nil).evmSwapFeeBigInt)
        XCTAssertEqual(SwapQuote.oneinch(makeQuote(swapFee: "5000000"), fee: nil).evmSwapFeeBigInt, 5_000_000)
        XCTAssertNil(SwapQuote.lifi(makeQuote(swapFee: "-1"), fee: nil, integratorFee: nil).evmSwapFeeBigInt)
        XCTAssertNil(SwapQuote.lifi(makeQuote(swapFee: "abc"), fee: nil, integratorFee: nil).evmSwapFeeBigInt)
    }

    // MARK: - LiFi EVM: what a missing fixed-fee entry means

    func testLiFiMissingFixedFeeIsStatedZeroOnlyWhenNoneWasRequested() {
        XCTAssertEqual(LiFiService.extractSwapFee(from: makeLiFiResponse(feeCosts: nil), integratorFee: 0).fee, "0")
        XCTAssertNil(LiFiService.extractSwapFee(from: makeLiFiResponse(feeCosts: []), integratorFee: Decimal(5) / 1000).fee)
        XCTAssertNil(LiFiService.extractSwapFee(from: makeLiFiResponse(feeCosts: nil), integratorFee: nil).fee)
    }

    func testLiFiFixedFeeEntryIsStatedVerbatim() {
        let response = makeLiFiResponse(feeCosts: [
            .init(name: "LIFI Fixed Fee", amount: "250000", included: true, token: .init(address: usdcContract))
        ])
        let extracted = LiFiService.extractSwapFee(from: response, integratorFee: Decimal(5) / 1000)
        XCTAssertEqual(extracted.fee, "250000")
        XCTAssertEqual(extracted.tokenContract, usdcContract)
    }

    // MARK: - Wire

    func testStatedZeroTravelsWithItsCoinContext() throws {
        let proto = SwapPayload.generic(makeGenericPayload(swapFee: "0", withContext: true)).mapToProtobuff()
        guard case let .oneinchSwapPayload(value) = proto else {
            XCTFail("Expected .oneinchSwapPayload"); return
        }
        XCTAssertEqual(value.quote.tx.swapFee, "0")
        XCTAssertTrue(value.quote.tx.hasSwapFeeChain)
        XCTAssertTrue(value.quote.tx.hasSwapFeeTokenID)
        XCTAssertTrue(value.quote.tx.hasSwapFeeDecimals)
        XCTAssertNotNil(
            try value.quote.tx.serializedData().range(of: Data([0x3a, 0x01, 0x30])),
            "field 7, length 1, \"0\" — the zero is present on the wire"
        )

        guard case let .generic(decoded) = try SwapPayload(proto: proto) else {
            XCTFail("Expected .generic"); return
        }
        XCTAssertEqual(decoded.quote.tx.swapFee, "0")
        XCTAssertEqual(decoded.swapFeeChain, "Ethereum")
        XCTAssertEqual(decoded.swapFeeTokenId, usdcContract)
        XCTAssertEqual(decoded.swapFeeDecimals, 6)
    }

    func testAbsentFeeLeavesTheWholeGroupOffTheWire() throws {
        let proto = SwapPayload.generic(makeGenericPayload(swapFee: nil, withContext: true)).mapToProtobuff()
        guard case let .oneinchSwapPayload(value) = proto else {
            XCTFail("Expected .oneinchSwapPayload"); return
        }
        XCTAssertTrue(value.quote.tx.swapFee.isEmpty)
        XCTAssertFalse(value.quote.tx.hasSwapFeeChain, "Coin context without an amount describes nothing")
        XCTAssertFalse(value.quote.tx.hasSwapFeeTokenID)
        XCTAssertFalse(value.quote.tx.hasSwapFeeDecimals)

        guard case let .generic(decoded) = try SwapPayload(proto: proto) else {
            XCTFail("Expected .generic"); return
        }
        XCTAssertNil(decoded.quote.tx.swapFee, "An empty wire string reads back as absent, not as \"\"")
    }

    func testLegacyWireBytesDecodeToAbsentAndReEncodeByteIdentical() throws {
        let originalBytes = try makeLegacyProto().serializedData()
        let decoded = try SwapPayload(proto: .oneinchSwapPayload(
            try VSOneInchSwapPayload(serializedBytes: originalBytes)
        ))
        guard case let .generic(payload) = decoded else {
            XCTFail("Expected .generic"); return
        }
        XCTAssertNil(payload.quote.tx.swapFee)
        XCTAssertNil(JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: decoded, vault: nil))

        guard case let .oneinchSwapPayload(reEncoded) = decoded.mapToProtobuff() else {
            XCTFail("Expected .oneinchSwapPayload"); return
        }
        XCTAssertEqual(
            try reEncoded.serializedData(), originalBytes,
            "A relayed legacy payload must re-serialize to the sender's exact bytes"
        )
    }

    func testKyberSwapProtoHasNoFeeFieldSoItDecodesToAbsent() throws {
        var proto = VSKyberSwapPayload()
        proto.fromCoin = ProtoCoinResolver.proto(from: makeETH())
        proto.toCoin = ProtoCoinResolver.proto(from: makeUSDC())
        proto.fromAmount = "1000000000000000000"
        proto.toAmountDecimal = "3000"
        proto.quote = .with {
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
        guard case let .generic(decoded) = try SwapPayload(proto: .kyberswapSwapPayload(proto)) else {
            XCTFail("Expected .generic"); return
        }
        XCTAssertNil(decoded.quote.tx.swapFee)
        XCTAssertNil(JoinKeysignSwapFeeViewModel().resolveSwapFee(swapPayload: .generic(decoded), vault: nil))
    }

    // MARK: - Co-signer

    func testCoSignerRendersAStatedZeroInTheContextCoin() {
        let resolved = JoinKeysignSwapFeeViewModel().resolveSwapFee(
            swapPayload: .generic(makeGenericPayload(swapFee: "0", withContext: true)),
            vault: nil
        )
        XCTAssertEqual(resolved?.amount, 0)
        XCTAssertEqual(resolved?.coin.ticker, "USDC")
    }

    func testCoSignerHidesAnAbsentFee() {
        XCTAssertNil(JoinKeysignSwapFeeViewModel().resolveSwapFee(
            swapPayload: .generic(makeGenericPayload(swapFee: nil, withContext: true)),
            vault: nil
        ))
    }

    func testCoSignerHidesAZeroWithoutCoinContext() {
        XCTAssertNil(
            JoinKeysignSwapFeeViewModel().resolveSwapFee(
                swapPayload: .generic(makeGenericPayload(swapFee: "0", withContext: false)),
                vault: nil
            ),
            "Never guess a coin, not even for a zero"
        )
    }

    // MARK: - LiFi Solana: the integrator fee stated in toCoin

    func testLiFiSolanaFeeIsTheIntegratorFractionOfTheOutputInToCoinUnits() {
        let usdc = makeCoin(.solana, ticker: "USDC", decimals: 6, isNative: false, contract: "EPjF")
        XCTAssertEqual(
            LiFiService.solanaSwapFee(toAmount: "100000000", integratorFee: Decimal(5) / 1000, toCoin: usdc),
            "500000"
        )
        XCTAssertEqual(LiFiService.solanaSwapFee(toAmount: "100000000", integratorFee: 0, toCoin: usdc), "0")
        XCTAssertNil(LiFiService.solanaSwapFee(toAmount: "100000000", integratorFee: nil, toCoin: usdc))
        XCTAssertNil(LiFiService.solanaSwapFee(toAmount: "not-a-number", integratorFee: 0, toCoin: usdc))
    }

    // MARK: - Fixtures

    private let usdcContract = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"

    private func makeGenericPayload(swapFee: String?, withContext: Bool) -> GenericSwapPayload {
        GenericSwapPayload(
            fromCoin: makeETH(),
            toCoin: makeUSDC(),
            fromAmount: BigInt("1000000000000000000"),
            toAmountDecimal: 3000,
            quote: makeQuote(swapFee: swapFee),
            provider: .kyberSwap,
            swapFeeChain: withContext ? "Ethereum" : nil,
            swapFeeTokenId: withContext ? usdcContract : nil,
            swapFeeDecimals: withContext ? 6 : nil
        )
    }

    /// Fields 1-7 only, `swap_fee` unset — the shape a sender predating the
    /// coin context sends for a route it states no fee on.
    private func makeLegacyProto() -> VSOneInchSwapPayload {
        var legacy = VSOneInchSwapPayload()
        legacy.fromCoin = ProtoCoinResolver.proto(from: makeETH())
        legacy.toCoin = ProtoCoinResolver.proto(from: makeUSDC())
        legacy.fromAmount = "1000000000000000000"
        legacy.toAmountDecimal = "3000"
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
        legacy.provider = "1inch"
        return legacy
    }

    private func makeETH() -> Coin {
        makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
    }

    private func makeUSDC() -> Coin {
        makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, contract: usdcContract)
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, contract: String = "") -> Coin {
        let asset = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "logo",
            decimals: decimals,
            priceProviderId: "stated-zero-\(ticker.lowercased())",
            contractAddress: contract,
            isNativeToken: isNative
        )
        return Coin(asset: asset, address: "stated-zero-\(ticker)", hexPublicKey: "")
    }

    private let baseTxJSON = #""from": "0xFrom", "to": "0xTo", "data": "0x", "value": "0", "gasPrice": "1", "gas": 100000"#

    private func decodeQuote(txJSON: String) throws -> EVMQuote {
        let json = #"{"dstAmount": "3000000000", "tx": {"# + txJSON + "}}"
        return try JSONDecoder().decode(EVMQuote.self, from: Data(json.utf8))
    }

    private func makeQuote(swapFee: String?) -> EVMQuote {
        EVMQuote(
            dstAmount: "3000000000",
            tx: EVMQuote.Transaction(
                from: "0xFrom", to: "0xRouter", data: "0x", value: "0", gasPrice: "1", gas: 100_000,
                swapFee: swapFee, swapFeeTokenContract: usdcContract
            )
        )
    }

    private func makeLiFiResponse(feeCosts: [LifiQuoteResponse.Estimate.FeeCost]?) -> LifiQuoteResponse.EvmQuoteResponse {
        .init(
            estimate: .init(
                toAmount: "3000000000",
                toAmountMin: "2990000000",
                executionDuration: 30,
                gasCosts: [],
                feeCosts: feeCosts
            ),
            transactionRequest: .init(
                data: "0x", to: "0xRouter", value: "0x0", from: "0xFrom", chainId: 1, gasLimit: "0x186a0", gasPrice: "0x1"
            )
        )
    }
}
