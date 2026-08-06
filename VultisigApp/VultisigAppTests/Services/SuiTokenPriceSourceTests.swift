//
//  SuiTokenPriceSourceTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class SuiTokenPriceSourceTests: XCTestCase {
    private static let canonicalContract =
        "0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd::custom::CUSTOM"
    private static let requestedContract =
        "0xABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD::custom::CUSTOM"

    func testCoinGeckoPlatformMapsSuiToSui() {
        XCTAssertEqual(CoinGeckoPlatform.id(for: .sui), "sui")
    }

    func testCoinGeckoPriceUsesRequestedContractKeyWithoutCallingFallback() async throws {
        let httpClient = SuiPriceHTTPClient(response: Data(
            #"{"\#(Self.canonicalContract)":{"usd":1.25}}"#.utf8
        ))
        let fallback = SuiFallbackPriceRecorder(value: 9.99)
        let source = SuiTokenPriceSource(
            httpClient: httpClient,
            fallbackPrice: { contract, decimals in
                await fallback.price(contract: contract, decimals: decimals)
            },
            currencyConverter: Self.usdOnlyConverter
        )

        let rates = try await source.prices(
            contracts: [Self.requestedContract],
            coins: [makeCoin(contract: Self.requestedContract, decimals: 7)]
        )

        XCTAssertEqual(rates, [Rate(fiat: "usd", crypto: SuiCoinType.rateKey(Self.requestedContract), value: 1.25)])
        let fallbackCalls = await fallback.calls
        XCTAssertEqual(fallbackCalls, [])

        let requests = await httpClient.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.path, "/coingeicko/api/v3/simple/token_price/sui")
        XCTAssertEqual(request.contractAddresses, Self.requestedContract)
    }

    func testMissingCoinGeckoPriceFallsBackUsingRuntimeCoinDecimals() async throws {
        let httpClient = SuiPriceHTTPClient(response: Data("{}".utf8))
        let fallback = SuiFallbackPriceRecorder(value: 2.5)
        let source = SuiTokenPriceSource(
            httpClient: httpClient,
            fallbackPrice: { contract, decimals in
                await fallback.price(contract: contract, decimals: decimals)
            },
            currencyConverter: Self.usdOnlyConverter
        )
        let runtimeDecimals = 3

        let rates = try await source.prices(
            contracts: [Self.requestedContract],
            coins: [makeCoin(contract: Self.requestedContract, decimals: runtimeDecimals)]
        )

        XCTAssertEqual(rates, [Rate(fiat: "usd", crypto: SuiCoinType.rateKey(Self.requestedContract), value: 2.5)])
        let fallbackCalls = await fallback.calls
        XCTAssertEqual(
            fallbackCalls,
            [.init(contract: Self.requestedContract, decimals: runtimeDecimals)]
        )
    }

    func testFallbackConvertsUSDPriceToSupportedCurrencies() async throws {
        let source = SuiTokenPriceSource(
            httpClient: SuiPriceHTTPClient(response: Data("{}".utf8)),
            fallbackPrice: { _, _ in 2.0 },
            currencyConverter: { usdPrice, currency in
                switch currency {
                case .USD: usdPrice
                case .AUD: usdPrice * 1.5
                default: nil
                }
            }
        )

        let rates = try await source.prices(
            contracts: [Self.requestedContract],
            coins: [makeCoin(contract: Self.requestedContract, decimals: 9)]
        )

        XCTAssertEqual(rates, [
            Rate(fiat: "usd", crypto: SuiCoinType.rateKey(Self.requestedContract), value: 2.0),
            Rate(fiat: "aud", crypto: SuiCoinType.rateKey(Self.requestedContract), value: 3.0)
        ])
    }

    func testZeroFallbackDoesNotEmitRateThatWouldOverwriteCache() async throws {
        let source = SuiTokenPriceSource(
            httpClient: SuiPriceHTTPClient(response: Data("{}".utf8)),
            fallbackPrice: { _, _ in 0 },
            currencyConverter: Self.usdOnlyConverter
        )

        let rates = try await source.prices(
            contracts: [Self.requestedContract],
            coins: [makeCoin(contract: Self.requestedContract, decimals: 9)]
        )

        XCTAssertTrue(rates.isEmpty)
    }

    func testEmptyCoinGeckoPriceMapFallsBack() async throws {
        let response = Data(#"{"\#(Self.canonicalContract)":{}}"#.utf8)
        let source = SuiTokenPriceSource(
            httpClient: SuiPriceHTTPClient(response: response),
            fallbackPrice: { _, _ in 4.0 },
            currencyConverter: Self.usdOnlyConverter
        )

        let rates = try await source.prices(
            contracts: [Self.requestedContract],
            coins: [makeCoin(contract: Self.requestedContract, decimals: 9)]
        )

        XCTAssertEqual(rates, [
            Rate(fiat: "usd", crypto: SuiCoinType.rateKey(Self.requestedContract), value: 4.0)
        ])
    }

    func testCaseDistinctMoveTypesUseDifferentRateKeys() {
        let uppercase = Self.requestedContract
        let lowercase = Self.requestedContract.replacingOccurrences(of: "CUSTOM", with: "custom")

        XCTAssertNotEqual(SuiCoinType.rateKey(uppercase), SuiCoinType.rateKey(lowercase))
        XCTAssertNotEqual(
            Rate.identifier(fiat: "usd", crypto: SuiCoinType.rateKey(uppercase)),
            Rate.identifier(fiat: "usd", crypto: SuiCoinType.rateKey(lowercase))
        )
    }

    func testCancelledCoinGeckoRequestDoesNotCallFallback() async {
        let fallback = SuiFallbackPriceRecorder(value: 2.5)
        let source = SuiTokenPriceSource(
            httpClient: CancelledSuiPriceHTTPClient(),
            fallbackPrice: { contract, decimals in
                await fallback.price(contract: contract, decimals: decimals)
            },
            currencyConverter: Self.usdOnlyConverter
        )

        do {
            _ = try await source.prices(
                contracts: [Self.requestedContract],
                coins: [makeCoin(contract: Self.requestedContract, decimals: 9)]
            )
            XCTFail("Expected cancellation to propagate")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        } catch {
            XCTFail("Expected URLError.cancelled, got \(error)")
        }

        let fallbackCalls = await fallback.calls
        XCTAssertTrue(fallbackCalls.isEmpty)
    }

    private static let usdOnlyConverter: SuiTokenPriceSource.CurrencyConverter = { usdPrice, currency in
        currency == .USD ? usdPrice : nil
    }

    private func makeCoin(contract: String, decimals: Int) -> CoinMeta {
        CoinMeta(
            chain: .sui,
            ticker: "CUSTOM",
            logo: .empty,
            decimals: decimals,
            priceProviderId: .empty,
            contractAddress: contract,
            isNativeToken: false
        )
    }
}

private actor CancelledSuiPriceHTTPClient: HTTPClientProtocol {
    func request(_: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        throw URLError(.cancelled)
    }
}

private actor SuiFallbackPriceRecorder {
    struct Call: Equatable {
        let contract: String
        let decimals: Int
    }

    private(set) var calls: [Call] = []
    private let value: Double

    init(value: Double) {
        self.value = value
    }

    func price(contract: String, decimals: Int) -> Double {
        calls.append(.init(contract: contract, decimals: decimals))
        return value
    }
}

private actor SuiPriceHTTPClient: HTTPClientProtocol {
    struct Request: Sendable {
        let path: String
        let contractAddresses: String?
    }

    private let response: Data
    private(set) var requests: [Request] = []

    init(response: Data) {
        self.response = response
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> { // swiftlint:disable:this async_without_await
        let contractAddresses: String?
        if case .requestParameters(let parameters, _) = target.task {
            contractAddresses = parameters["contract_addresses"] as? String
        } else {
            contractAddresses = nil
        }
        requests.append(.init(path: target.path, contractAddresses: contractAddresses))

        let url = target.baseURL.appendingPathComponent(target.path)
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return HTTPResponse(data: response, response: httpResponse)
    }
}
