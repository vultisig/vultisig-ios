//
//  SendRippleDestinationGuardTests.swift
//  VultisigAppTests
//
//  Covers the Verify-stage wiring of the XRP destination-activation guard:
//  `SendCryptoVerifyLogic.validateDestinationIfNeeded` runs the RippleService
//  check for native XRP sends only — every other chain must pass through
//  without touching the network.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendRippleDestinationGuardTests: XCTestCase {

    private var token: TestContextToken?

    override func setUp() async throws {
        try await super.setUp()
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(token)
        token = nil
        try await super.tearDown()
    }

    func testNonRippleSendSkipsDestinationLookup() async throws {
        // The client trips on ANY request — passing proves no network access.
        let client = TrippingHTTPClient()
        let logic = makeLogic(client: client)
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18)
        let tx = makeTransaction(coin: eth, amount: "0.1")

        try await logic.validateDestinationIfNeeded(tx: tx)
        XCTAssertEqual(client.requestCount, 0)
    }

    func testRippleSendToFundedDestinationPasses() async throws {
        let client = TrippingHTTPClient()
        client.accountInfoResult = .success(Data("""
        {"result":{"account_data":{"Account":"rFunded","Balance":"20000000","OwnerCount":0,"Sequence":7},"status":"success","validated":true}}
        """.utf8))
        let logic = makeLogic(client: client)
        let xrp = makeCoin(.ripple, ticker: Chain.ripple.ticker, decimals: 6)
        let tx = makeTransaction(coin: xrp, amount: "0.5")

        try await logic.validateDestinationIfNeeded(tx: tx)
        XCTAssertEqual(client.requestCount, 1)
    }

    func testRippleSendToUnfundedDestinationBelowReserveThrows() async throws {
        let client = TrippingHTTPClient()
        client.accountInfoResult = .success(Data("""
        {"result":{"error":"actNotFound","error_code":19,"error_message":"Account not found.","status":"error","validated":false}}
        """.utf8))
        client.serverStateResult = .success(Data("""
        {"result":{"state":{"load_base":256,"load_factor":256,"validated_ledger":{"base_fee":10,"reserve_base":1000000,"reserve_inc":200000}}}}
        """.utf8))
        let logic = makeLogic(client: client)
        let xrp = makeCoin(.ripple, ticker: Chain.ripple.ticker, decimals: 6)
        // 0.5 XRP = 500,000 drops < the 1 XRP base reserve.
        let tx = makeTransaction(coin: xrp, amount: "0.5")

        do {
            try await logic.validateDestinationIfNeeded(tx: tx)
            XCTFail("a sub-reserve send to an unfunded XRP destination must be blocked before the ceremony")
        } catch let error as HelperError {
            // Rewrapped for the Verify screen's alert plumbing, which presents
            // only HelperError; the message must carry the localized copy.
            guard case .runtimeError(let message) = error else {
                return XCTFail("unexpected HelperError: \(error)")
            }
            XCTAssertTrue(message.contains("XRP"), "expected the destination-activation copy, got: \(message)")
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    // MARK: - Fixtures

    private func makeLogic(client: HTTPClientProtocol) -> SendCryptoVerifyLogic {
        SendCryptoVerifyLogic(
            interactor: MockSendInteractor(),
            rippleService: RippleService(resolver: NoOverrideResolver(), httpClient: client)
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int) -> Coin {
        var asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: true)
        asset.priceProviderId = "dest-guard-\(ticker)-\(UUID().uuidString)"
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = "100000000"
        return coin
    }

    private func makeTransaction(coin: Coin, amount: String) -> SendTransaction {
        let vault = TestStore.makeVault()
        return SendTransaction(
            coin: coin,
            vault: vault,
            fromAddress: coin.address,
            toAddress: "rDestinationAddressUnderTest",
            toAddressLabel: nil,
            amount: amount,
            amountInFiat: "",
            memo: "",
            gas: BigInt.zero,
            fee: BigInt(20),
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin
        )
    }
}

// MARK: - Test doubles

private struct NoOverrideResolver: RPCEndpointResolving {
    // swiftlint:disable:next unused_parameter
    func url(for chain: Chain) -> String? { nil }
}

// `async` is required by `HTTPClientProtocol`; the stub answers synchronously.
// swiftlint:disable async_without_await

/// Scripted client that counts requests and fails on anything unscripted, so a
/// test can prove a code path never touches the network.
private final class TrippingHTTPClient: HTTPClientProtocol, @unchecked Sendable {

    var accountInfoResult: Result<Data, Error> = .failure(URLError(.badServerResponse))
    var serverStateResult: Result<Data, Error> = .failure(URLError(.badServerResponse))

    private let queue = DispatchQueue(label: "TrippingHTTPClient.queue")
    private var _requestCount = 0

    var requestCount: Int {
        queue.sync { _requestCount }
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        queue.sync { _requestCount += 1 }
        guard let api = target as? RippleAPI else {
            throw URLError(.unsupportedURL)
        }
        switch api.endpoint {
        case .accountInfo:
            return try respond(accountInfoResult)
        case .serverState:
            return try respond(serverStateResult)
        case .submit, .tx:
            throw URLError(.unsupportedURL)
        }
    }

    private func respond(_ result: Result<Data, Error>) throws -> HTTPResponse<Data> {
        let data = try result.get()
        guard let url = URL(string: "https://xrplcluster.com"),
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else {
            throw URLError(.badURL)
        }
        return HTTPResponse(data: data, response: response)
    }
}

// swiftlint:enable async_without_await
