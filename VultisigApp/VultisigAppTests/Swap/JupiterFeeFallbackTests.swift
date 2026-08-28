//
//  JupiterFeeFallbackTests.swift
//  VultisigAppTests
//
//  Missing fee ATA / fee-bearing 4xx must requote Jupiter without a platform
//  fee instead of throwing JupiterError out of fetchQuote.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class JupiterFeeFallbackTests: XCTestCase {

    private let wsol = JupiterService.wrappedSolMint
    private let usdc = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

    func testMissingFeeAtaQuotesWithoutPlatformFee() async throws {
        let accounts = StubSolanaAccounts(feeAtaExists: false)
        let http = JupiterScriptedHTTPClient(
            quoteScript: [(200, quoteJSON(input: wsol, output: usdc, feeAmount: nil))]
        )
        let service = JupiterService(httpClient: http, solanaService: accounts)

        let result = try await service.fetchQuote(
            fromCoin: makeSOL(),
            toCoin: makeUSDC(),
            fromAmount: 1_000_000_000,
            vultTierDiscount: 0,
            slippageBps: 50
        )

        XCTAssertEqual(http.quotedFeeBps, [nil], "missing ATA must omit platformFeeBps")
        XCTAssertFalse(http.swapRequestedFeeAccount, "missing ATA must omit feeAccount on /swap")
        XCTAssertEqual(result.quote.dstAmount, "1500000")
        XCTAssertEqual(result.platformFee, 0)
    }

    func testProvisionedFeeAtaSendsPlatformFee() async throws {
        let accounts = StubSolanaAccounts(feeAtaExists: true)
        let http = JupiterScriptedHTTPClient(
            quoteScript: [(200, quoteJSON(input: wsol, output: usdc, feeAmount: "7500"))]
        )
        let service = JupiterService(httpClient: http, solanaService: accounts)

        let result = try await service.fetchQuote(
            fromCoin: makeSOL(),
            toCoin: makeUSDC(),
            fromAmount: 1_000_000_000,
            vultTierDiscount: 0,
            slippageBps: 50
        )

        XCTAssertEqual(http.quotedFeeBps, [50])
        XCTAssertTrue(http.swapRequestedFeeAccount)
        XCTAssertGreaterThan(result.platformFee, 0)
    }

    func testFeeBearingQuote4xxRetriesWithoutFee() async throws {
        let accounts = StubSolanaAccounts(feeAtaExists: true)
        let http = JupiterScriptedHTTPClient(
            quoteScript: [
                (400, #"{"error":"The token is not tradable"}"#),
                (200, quoteJSON(input: wsol, output: usdc, feeAmount: nil))
            ]
        )
        let service = JupiterService(httpClient: http, solanaService: accounts)

        let result = try await service.fetchQuote(
            fromCoin: makeSOL(),
            toCoin: makeUSDC(),
            fromAmount: 1_000_000_000,
            vultTierDiscount: 0,
            slippageBps: 50
        )

        XCTAssertEqual(http.quotedFeeBps, [50, nil])
        XCTAssertFalse(http.swapRequestedFeeAccount)
        XCTAssertEqual(result.quote.dstAmount, "1500000")
    }

    private func makeSOL() -> Coin {
        makeCoin(.solana, ticker: "SOL", decimals: 9, isNative: true)
    }

    private func makeUSDC() -> Coin {
        makeCoin(
            .solana, ticker: "USDC", decimals: 6, isNative: false,
            contract: usdc
        )
    }

    private func makeCoin(
        _ chain: Chain,
        ticker: String,
        decimals: Int,
        isNative: Bool,
        contract: String = ""
    ) -> Coin {
        let meta = CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: "logo",
            decimals: decimals,
            priceProviderId: ticker.lowercased(),
            contractAddress: contract,
            isNativeToken: isNative
        )
        return Coin(asset: meta, address: "HzqJovNiVvGrGNiiYvEozEVgZ58xaU3RKwX8eACQBCt3", hexPublicKey: "")
    }

    private func quoteJSON(input: String, output: String, feeAmount: String?) -> String {
        let fee: String
        if let feeAmount {
            fee = #""platformFee":{"amount":"\#(feeAmount)","feeBps":50},"#
        } else {
            fee = ""
        }
        return """
        {
          "inputMint": "\(input)",
          "outputMint": "\(output)",
          "outAmount": "1500000",
          \(fee)
          "routePlan": []
        }
        """
    }
}

private struct StubSolanaAccounts: SolanaAccountChecking {
    var mintExists = true
    var isToken2022 = false
    var feeAtaExists: Bool

    // Protocol requires `async`; the body is synchronous.
    // swiftlint:disable:next async_without_await
    func checkAccountExists(address: String) async throws -> (exists: Bool, isToken2022: Bool) {
        if address == "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" {
            return (mintExists, isToken2022)
        }
        return (feeAtaExists, isToken2022)
    }
}

private final class JupiterScriptedHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var quoteScript: [(Int, String)]
    private(set) var quotedFeeBps: [Int?] = []
    private(set) var swapRequestedFeeAccount = false

    init(quoteScript: [(Int, String)]) {
        self.quoteScript = quoteScript
    }

    // Protocol requires `async`; the body is synchronous.
    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        guard let api = target as? JupiterAPI else {
            throw HTTPError.invalidURL
        }
        switch api {
        case .quote(let params):
            let step: (Int, String) = lock.withLock {
                quotedFeeBps.append(params.platformFeeBps)
                return quoteScript.removeFirst()
            }
            if step.0 >= 400 {
                throw HTTPError.statusCode(step.0, Data(step.1.utf8))
            }
            return ok(step.1)
        case .swap(let body):
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                lock.withLock { swapRequestedFeeAccount = json["feeAccount"] != nil }
            }
            return ok(#"{"swapTransaction":"AQID"}"#)
        }
    }

    private func ok(_ json: String) -> HTTPResponse<Data> {
        let url = URL(string: "https://api.vultisig.com/jup/swap/v1/quote")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: Data(json.utf8), response: response)
    }
}
