//
//  ProviderProtocolFeeTests.swift
//  VultisigAppTests
//
//  The aggregator's own charge (LI.FI's share of its fixed fee, SwapKit's
//  `service` fee) is itemized on the Protocol Fee row, apart from the Vultisig
//  affiliate row, and counted in the total.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class ProviderProtocolFeeTests: XCTestCase {

    private let usdcContract = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

    // MARK: - LI.FI fixed-fee split

    func testLiFiSplitsTheFixedFeeEntryByFeeSplit() {
        let costs = [makeFeeCost(amount: "55000", token: "11111111111111111111111111111111", integrator: "30000")]
        let fee = LiFiService.extractProtocolFee(from: costs)
        XCTAssertEqual(fee?.fee, "25000")
        XCTAssertEqual(fee?.tokenContract, "", "The Solana native mint is a native fee, not a contract")
    }

    func testLiFiSplitKeepsTheFeeTokenContract() {
        let costs = [makeFeeCost(amount: "400000", token: usdcContract, integrator: "250000")]
        let fee = LiFiService.extractProtocolFee(from: costs)
        XCTAssertEqual(fee?.fee, "150000")
        XCTAssertEqual(fee?.tokenContract, usdcContract)
    }

    func testLiFiEntryWithoutASplitYieldsNoProtocolFee() {
        XCTAssertNil(LiFiService.extractProtocolFee(from: [makeFeeCost(amount: "55000", token: nil, integrator: nil)]))
        XCTAssertNil(LiFiService.extractProtocolFee(from: nil))
    }

    func testLiFiIntegratorShareAtOrAboveTheTotalLeavesNoProviderShare() {
        XCTAssertNil(LiFiService.extractProtocolFee(from: [makeFeeCost(amount: "30000", token: nil, integrator: "30000")]))
        XCTAssertNil(LiFiService.extractProtocolFee(from: [makeFeeCost(amount: "30000", token: nil, integrator: "45000")]))
    }

    func testLiFiOnlyTheFixedFeeEntryIsSplit() {
        let other = LifiQuoteResponse.Estimate.FeeCost(
            name: "Gas Fee", amount: "9", included: false, token: nil,
            feeSplit: .init(integratorFee: "1", lifiFee: "8")
        )
        XCTAssertNil(LiFiService.extractProtocolFee(from: [other]))
    }

    func testLiFiFeeSplitDecodesFromTheWire() throws {
        let json = """
        {"name":"LIFI Fixed Fee","amount":"55000","included":false,
         "token":{"address":"11111111111111111111111111111111"},
         "feeSplit":{"integratorFee":"30000","lifiFee":"25000"}}
        """
        let cost = try JSONDecoder().decode(LifiQuoteResponse.Estimate.FeeCost.self, from: Data(json.utf8))
        XCTAssertEqual(cost.feeSplit?.integratorFee, "30000")
        XCTAssertEqual(LiFiService.extractProtocolFee(from: [cost])?.fee, "25000")
    }

    func testLiFiFeeEntryWithoutASplitStillDecodes() throws {
        let json = #"{"name":"LIFI Fixed Fee","amount":"1","included":true,"token":null}"#
        let cost = try JSONDecoder().decode(LifiQuoteResponse.Estimate.FeeCost.self, from: Data(json.utf8))
        XCTAssertNil(cost.feeSplit)
    }

    // MARK: - LI.FI display (EVM: swapFee is the whole charge)

    func testLiFiEvmAffiliateExcludesTheProviderShareAndProtocolRowCarriesIt() {
        let eth = makeCoin(.ethereum, ticker: "ETHPFE1", decimals: 18, isNative: true)
        let usdc = makeCoin(.ethereum, ticker: "USDCPFE1", decimals: 6, isNative: false)
        setPrice(2000, for: eth)
        setPrice(1, for: usdc)
        let quote = makeLiFiQuote(swapFee: "550000000000000", protocolFee: "250000000000000", protocolContract: "")

        let affiliate = SwapCryptoLogic.affiliateFeeFiat(quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth)
        let provider = SwapCryptoLogic.protocolFeeFiat(quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth)

        XCTAssertEqual(affiliate, Decimal(string: "0.6"))
        XCTAssertEqual(provider, Decimal(string: "0.5"))
        XCTAssertTrue(SwapCryptoLogic.showProtocolFeeRow(
            quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth, mode: .standard
        ))
    }

    func testLiFiTotalFeeCountsBothCuts() {
        let eth = makeCoin(.ethereum, ticker: "ETHPFE2", decimals: 18, isNative: true)
        let usdc = makeCoin(.ethereum, ticker: "USDCPFE2", decimals: 6, isNative: false)
        setPrice(2000, for: eth)
        setPrice(1, for: usdc)
        let quote = makeLiFiQuote(swapFee: "550000000000000", protocolFee: "250000000000000", protocolContract: "")

        let total = SwapCryptoLogic.totalFeeString(
            quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth, fee: .zero
        )
        XCTAssertEqual(total, Decimal(string: "1.1")?.formatToFiatForFee(includeCurrencySymbol: true))
    }

    func testLiFiWithoutAProviderShareShowsNoProtocolRow() {
        let eth = makeCoin(.ethereum, ticker: "ETHPFE3", decimals: 18, isNative: true)
        let usdc = makeCoin(.ethereum, ticker: "USDCPFE3", decimals: 6, isNative: false)
        let quote = makeLiFiQuote(swapFee: "550000000000000", protocolFee: nil, protocolContract: "")

        XCTAssertFalse(SwapCryptoLogic.showProtocolFeeRow(
            quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth, mode: .standard
        ))
        XCTAssertEqual(SwapCryptoLogic.protocolFeeFiat(quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth), 0)
    }

    func testLiFiFeeInACoinTheSwapDoesNotInvolveIsNotPriced() {
        let eth = makeCoin(.ethereum, ticker: "ETHPFE4", decimals: 18, isNative: true)
        let usdc = makeCoin(.ethereum, ticker: "USDCPFE4", decimals: 6, isNative: false)
        let quote = makeLiFiQuote(swapFee: "550000", protocolFee: "250000", protocolContract: "0xdeadbeef")

        XCTAssertNil(SwapCryptoLogic.providerFee(quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth))
    }

    func testLiFiAffiliateKeepsTheWholeFeeWhenTheProviderShareCannotBePriced() {
        let eth = makeCoin(.ethereum, ticker: "ETHPFE6", decimals: 18, isNative: true)
        let usdc = makeCoin(.ethereum, ticker: "USDCPFE6", decimals: 6, isNative: false)
        setPrice(2000, for: eth)
        setPrice(1, for: usdc)
        let quote = makeLiFiQuote(swapFee: "550000000000000", protocolFee: "250000000000000", protocolContract: "0xdeadbeef")

        let affiliate = SwapCryptoLogic.affiliateFeeFiat(quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth)
        XCTAssertEqual(affiliate, Decimal(string: "1.1"))
    }

    // MARK: - LI.FI display (Solana: swapFee is the integrator's cut alone)

    func testLiFiSolanaAffiliateIsUntouchedAndProtocolIsAdditional() {
        let sol = makeCoin(.solana, ticker: "SOLPFE5", decimals: 9, isNative: true)
        let usdc = makeCoin(.solana, ticker: "USDCPFE5", decimals: 6, isNative: false)
        setPrice(100, for: sol)
        setPrice(1, for: usdc)
        // 1 USDC out at 30 bps is 0.003 USDC; LI.FI's 25000 lamports sit on top.
        let quote = makeLiFiQuote(
            swapFee: "3000", swapFeeContract: "", protocolFee: "25000", protocolContract: "",
            integratorFee: Decimal(3) / 1000, dstAmount: "1000000"
        )

        let affiliate = SwapCryptoLogic.affiliateFeeFiat(quote: quote, fromCoin: sol, toCoin: usdc, feeCoin: sol)
        let provider = SwapCryptoLogic.protocolFeeFiat(quote: quote, fromCoin: sol, toCoin: usdc, feeCoin: sol)

        XCTAssertEqual(affiliate, Decimal(string: "0.003"))
        XCTAssertEqual(provider, Decimal(string: "0.0025"))
    }

    // MARK: - SwapKit service fee

    func testSwapKitServiceFeeIsTheProtocolFeeAndTheAffiliateIsNot() {
        let (eth, usdc) = makeEthUsdc(suffix: "SK1")
        let response = makeSwapKitResponse(fees: [
            ("affiliate", "0.30", "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48"),
            ("service", "0.15", "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48")
        ])

        let fee = SwapCryptoLogic.swapKitServiceFee(response: response, fromCoin: eth, toCoin: usdc)
        XCTAssertEqual(fee?.amount, Decimal(string: "0.15"))
        XCTAssertEqual(fee?.coin.ticker, usdc.ticker)
    }

    func testSwapKitServiceFeesSumWithinOneAsset() {
        let (eth, usdc) = makeEthUsdc(suffix: "SK2")
        let response = makeSwapKitResponse(fees: [
            ("service", "0.10", "ETH.USDC-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"),
            ("service", "0.05", "ETH.USDC-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        ])
        XCTAssertEqual(SwapCryptoLogic.swapKitServiceFee(response: response, fromCoin: eth, toCoin: usdc)?.amount, Decimal(string: "0.15"))
    }

    func testSwapKitServiceFeeInTheSellAssetResolvesToTheFromCoin() {
        let (eth, usdc) = makeEthUsdc(suffix: "SK3")
        let response = makeSwapKitResponse(fees: [("service", "0.001", "ETH.ETH")])
        XCTAssertEqual(SwapCryptoLogic.swapKitServiceFee(response: response, fromCoin: eth, toCoin: usdc)?.coin.ticker, eth.ticker)
    }

    func testSwapKitServiceFeeIsLeftOutWhenItsShapeCannotBeResolved() {
        let (eth, usdc) = makeEthUsdc(suffix: "SK4")
        // Mixed assets, an unrelated asset, a negative amount, a zero amount, and no service entry at all.
        let mixed = makeSwapKitResponse(fees: [("service", "0.1", "ETH.ETH"), ("service", "0.1", "ETH.USDC-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")])
        let unrelated = makeSwapKitResponse(fees: [("service", "0.1", "BTC.BTC")])
        let negative = makeSwapKitResponse(fees: [("service", "-0.1", "ETH.ETH")])
        let zero = makeSwapKitResponse(fees: [("service", "0", "ETH.ETH")])
        let affiliateOnly = makeSwapKitResponse(fees: [("affiliate", "0.1", "ETH.ETH")])

        for response in [mixed, unrelated, negative, zero, affiliateOnly] {
            XCTAssertNil(SwapCryptoLogic.swapKitServiceFee(response: response, fromCoin: eth, toCoin: usdc))
        }
    }

    func testSwapKitProtocolRowShowsAndAffiliateStaysIncludedInRate() {
        let (eth, usdc) = makeEthUsdc(suffix: "SK5")
        setPrice(2000, for: eth)
        setPrice(1, for: usdc)
        let response = makeSwapKitResponse(fees: [
            ("affiliate", "0.30", "ETH.USDC-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"),
            ("service", "0.15", "ETH.USDC-0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")
        ])
        let quote = SwapQuote.swapkit(response, fee: nil, subProvider: "Chainflip")

        XCTAssertTrue(SwapCryptoLogic.showProtocolFeeRow(
            quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth, mode: .standard
        ))
        XCTAssertEqual(SwapCryptoLogic.protocolFeeFiat(quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth), Decimal(string: "0.15"))
        XCTAssertEqual(SwapCryptoLogic.affiliateFeeFiat(quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth), 0)
        XCTAssertEqual(
            SwapCryptoLogic.totalFeeString(quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth, fee: .zero),
            Decimal(string: "0.15")?.formatToFiatForFee(includeCurrencySymbol: true)
        )
    }

    func testSwapKitProtocolRowIsSuppressedForASecuredMint() {
        let (eth, usdc) = makeEthUsdc(suffix: "SK6")
        let response = makeSwapKitResponse(fees: [("service", "0.001", "ETH.ETH")])
        let quote = SwapQuote.swapkit(response, fee: nil, subProvider: "Chainflip")
        XCTAssertFalse(SwapCryptoLogic.showProtocolFeeRow(
            quote: quote, fromCoin: eth, toCoin: usdc, feeCoin: eth, mode: .securedMint
        ))
    }

    // MARK: - Fixtures

    private func makeFeeCost(amount: String, token: String?, integrator: String?) -> LifiQuoteResponse.Estimate.FeeCost {
        .init(
            name: "LIFI Fixed Fee", amount: amount, included: false,
            token: token.map { .init(address: $0) },
            feeSplit: integrator.map { .init(integratorFee: $0, lifiFee: nil) }
        )
    }

    private func makeLiFiQuote(
        swapFee: String?,
        swapFeeContract: String = "",
        protocolFee: String?,
        protocolContract: String,
        integratorFee: Decimal? = Decimal(5) / 1000,
        dstAmount: String = "1000000"
    ) -> SwapQuote {
        let evm = EVMQuote(
            dstAmount: dstAmount,
            tx: EVMQuote.Transaction(
                from: "from", to: "to", data: "0x", value: "0", gasPrice: "0", gas: 0,
                swapFee: swapFee, swapFeeTokenContract: swapFeeContract,
                protocolFee: protocolFee, protocolFeeTokenContract: protocolContract
            )
        )
        return .lifi(evm, fee: nil, integratorFee: integratorFee)
    }

    private func makeEthUsdc(suffix: String) -> (Coin, Coin) {
        let eth = makeCoin(.ethereum, ticker: "ETH\(suffix)", decimals: 18, isNative: true)
        let usdc = makeCoin(.ethereum, ticker: "USDC\(suffix)", decimals: 6, isNative: false, contract: usdcContract)
        return (eth, usdc)
    }

    private func makeSwapKitResponse(fees: [(type: String, amount: String, asset: String)]) -> SwapKitSwapResponse {
        let feeJSON = fees.map {
            #"{"type":"\#($0.type)","amount":"\#($0.amount)","asset":"\#($0.asset)","chain":"ETH","protocol":"Chainflip"}"#
        }.joined(separator: ",")
        let json = """
        {
          "swapId": "s", "routeId": "r", "providers": ["Chainflip"],
          "sellAsset": "ETH.ETH", "buyAsset": "ETH.USDC-0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
          "sellAmount": "1", "expectedBuyAmount": "2000", "expectedBuyAmountMaxSlippage": "1990",
          "sourceAddress": "from", "destinationAddress": "to", "targetAddress": "target",
          "meta": { "txType": "EVM" },
          "tx": { "from": "from", "to": "to", "value": "0", "data": "0x", "gas": "0x30d40", "gasPrice": "0x4a817c800" },
          "fees": [\(feeJSON)]
        }
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(SwapKitSwapResponse.self, from: Data(json.utf8))
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, contract: String = "") -> Coin {
        let asset = CoinMeta(
            chain: chain, ticker: ticker, logo: "logo", decimals: decimals,
            priceProviderId: ticker.lowercased(), contractAddress: contract, isNativeToken: isNative
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
        XCTAssertEqual(coin.price, value, accuracy: 0.0001, "Rate for \(coin.ticker) did not take effect")
    }
}
