//
//  SuiServiceBalanceTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

final class SuiServiceBalanceTests: XCTestCase {
    private static let stubHost = "sui-balance-stub.local"
    private static let owner = "0xowner"
    private static let nativeLong = "0x" + String(repeating: "0", count: 63) + "2::sui::SUI"
    private static let xSui = "0xb45f7a8e2d1c4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a::xsui::XSUI"
    private static let bridgedCoin = "0x5d4b302506645c37ff133b98c4b50a5ae14841659738d6d733d59d0d217a93bf::coin::COIN"

    override func setUp() {
        super.setUp()
        SuiBalanceRPCStub.configure(response: Data("{}".utf8))
        URLProtocol.registerClass(SuiBalanceRPCStub.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(SuiBalanceRPCStub.self)
        SuiBalanceRPCStub.configure(response: Data("{}".utf8))
        super.tearDown()
    }

    func testNativeBalanceUsesExactNormalizedCoinType() async throws {
        SuiBalanceRPCStub.configure(response: Self.balancesResponse([
            (Self.xSui, "999"),
            (Self.nativeLong, "123")
        ]))
        let service = makeService()

        let balance = try await service.getBalance(coin: TokensStore.Token.suiSUI, address: Self.owner)

        XCTAssertEqual(balance, "123")
    }

    func testTokenBalanceMatchesContractWhenTickerDiffersFromStructName() async throws {
        let unrelatedUSDC = "0xabc::usdc::USDC"
        SuiBalanceRPCStub.configure(response: Self.balancesResponse([
            (unrelatedUSDC, "999"),
            (Self.bridgedCoin, "456")
        ]))
        let service = makeService()
        let coin = CoinMeta(
            chain: .sui,
            ticker: "USDC",
            logo: "",
            decimals: 6,
            priceProviderId: "",
            contractAddress: Self.bridgedCoin,
            isNativeToken: false
        )

        let balance = try await service.getBalance(coin: coin, address: Self.owner)

        XCTAssertEqual(balance, "456")
    }

    func testEmptySuccessfulResultReturnsZero() async throws {
        SuiBalanceRPCStub.configure(response: Self.balancesResponse([]))

        let balance = try await makeService().getBalance(coin: TokensStore.Token.suiSUI, address: Self.owner)

        XCTAssertEqual(balance, "0")
    }

    func testTransportFailureIsPropagated() async {
        SuiBalanceRPCStub.configure(error: URLError(.timedOut))

        do {
            _ = try await makeService().getBalance(coin: TokensStore.Token.suiSUI, address: Self.owner)
            XCTFail("Expected the transport error to be propagated")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .timedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testJSONRPCErrorIsPropagated() async {
        SuiBalanceRPCStub.configure(response: Data(
            #"{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"node unavailable"}}"#.utf8
        ))

        do {
            _ = try await makeService().getBalance(coin: TokensStore.Token.suiSUI, address: Self.owner)
            XCTFail("Expected the JSON-RPC error to be propagated")
        } catch SuiBalanceError.rpc(let message) {
            XCTAssertEqual(message, "node unavailable")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMissingResultIsPropagated() async {
        SuiBalanceRPCStub.configure(response: Data(#"{"jsonrpc":"2.0","id":1}"#.utf8))

        do {
            _ = try await makeService().getBalance(coin: TokensStore.Token.suiSUI, address: Self.owner)
            XCTFail("Expected a malformed response error")
        } catch SuiBalanceError.missingResult {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeService() -> SuiService {
        SuiService(resolver: SuiBalanceRPCResolver(host: Self.stubHost))
    }

    private static func balancesResponse(_ balances: [(coinType: String, totalBalance: String)]) -> Data {
        let entries = balances.map {
            #"{"coinType":"\#($0.coinType)","coinObjectCount":1,"totalBalance":"\#($0.totalBalance)","lockedBalance":{}}"#
        }
        return Data(#"{"jsonrpc":"2.0","id":1,"result":[\#(entries.joined(separator: ","))]}"#.utf8)
    }
}

private struct SuiBalanceRPCResolver: RPCEndpointResolving {
    let host: String

    func url(for _: Chain) -> String? {
        "https://\(host)/rpc"
    }
}

private final class SuiBalanceRPCStub: URLProtocol {
    private enum Outcome {
        case response(Data)
        case error(Error)
    }

    private static let lock = NSLock()
    private static var outcome = Outcome.response(Data("{}".utf8))

    static func configure(response: Data) {
        lock.withLock {
            outcome = .response(response)
        }
    }

    static func configure(error: Error) {
        lock.withLock {
            outcome = .error(error)
        }
    }

    // swiftlint:disable static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "sui-balance-stub.local"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        let configuredOutcome = Self.lock.withLock { Self.outcome }

        switch configuredOutcome {
        case .response(let data):
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badURL))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .error(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
