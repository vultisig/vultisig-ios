//
//  SwapVerifyHaltGateTests.swift
//  VultisigAppTests
//
//  Sign-time halt block (HIGH security): the pre-flight re-check bypasses the
//  inbound cache and blocks signing when the source chain is halted. The gate
//  now lives in `DefaultSwapInteractor` (so the verify VM holds no chain
//  service); these tests drive the interactor's inbound clients directly, plus
//  a thin VM-delegation check that the VM surfaces the thrown error.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapVerifyHaltGateTests: XCTestCase {

    func testHaltedSourceChainBlocksSigning() async {
        let interactor = makeInteractor(mayaInbound: haltedArbInbound)
        await assertThrowsTradingHalted {
            try await interactor.assertSourceChainNotHalted(transaction: makeTransaction())
        }
    }

    func testNonHaltedSourceChainProceeds() async throws {
        let interactor = makeInteractor(mayaInbound: openArbInbound)
        try await interactor.assertSourceChainNotHalted(transaction: makeTransaction())
    }

    func testHaltReCheckBypassesCache() async {
        // The sign-time fetch must issue a fresh request every time (bypassCache)
        // rather than serving a stale cached entry.
        let stub = PathStubClient(responses: ["/mayachain/inbound_addresses": haltedArbInbound])
        let interactor = makeInteractor(maya: MayachainService(httpClient: stub))
        _ = try? await interactor.assertSourceChainNotHalted(transaction: makeTransaction())
        _ = try? await interactor.assertSourceChainNotHalted(transaction: makeTransaction())
        let count = await stub.requestCount
        XCTAssertEqual(count, 2, "Each sign-time re-check must bypass the cache and refetch")
    }

    // MARK: - Aggregator routes skip the preflight

    func testAggregatorRouteSkipsPreflightEvenOnHaltedChain() async throws {
        // Even though the source chain's Maya inbound is halted, a 1inch route
        // never deposits there — the preflight is skipped and signing proceeds.
        let stub = PathStubClient(responses: ["/mayachain/inbound_addresses": haltedArbInbound])
        let interactor = makeInteractor(maya: MayachainService(httpClient: stub))
        try await interactor.assertSourceChainNotHalted(
            transaction: makeTransaction(quote: .oneinch(makeEVMQuote(), fee: nil))
        )
        let count = await stub.requestCount
        XCTAssertEqual(count, 0, "Aggregator routes must not fetch any inbound")
    }

    // MARK: - Native routes fail CLOSED on an unverifiable fetch

    func testNativeRouteFailsClosedWhenInboundFetchThrows() async {
        // The Maya inbound endpoint returns a 501 (no stubbed response) → the
        // throwing fetch propagates → the native route is BLOCKED, not allowed.
        let interactor = makeInteractor(maya: MayachainService(httpClient: PathStubClient(responses: [:])))
        await assertThrowsTradingHalted {
            try await interactor.assertSourceChainNotHalted(transaction: makeTransaction())
        }
    }

    // MARK: - VM delegation

    func testVMReturnsFalseAndSetsErrorWhenGateThrows() async {
        let vm = SwapVerifyViewModel(transaction: makeTransaction(), interactor: StubGateInteractor(throwError: SwapError.tradingHalted))
        let safe = await vm.isSourceChainSafeToSign()
        XCTAssertFalse(safe)
        XCTAssertEqual((vm.error as? SwapError), .tradingHalted)
    }

    func testVMReturnsTrueWhenGatePasses() async {
        let vm = SwapVerifyViewModel(transaction: makeTransaction(), interactor: StubGateInteractor(throwError: nil))
        let safe = await vm.isSourceChainSafeToSign()
        XCTAssertTrue(safe)
        XCTAssertNil(vm.error)
    }

    // MARK: - Helpers

    private func makeInteractor(mayaInbound: Data) -> DefaultSwapInteractor {
        makeInteractor(maya: MayachainService(httpClient: PathStubClient(responses: ["/mayachain/inbound_addresses": mayaInbound])))
    }

    private func makeInteractor(maya: MayachainService) -> DefaultSwapInteractor {
        DefaultSwapInteractor(
            quote: SwapService.shared,
            blockchain: BlockChainService.shared,
            balance: BalanceService.shared,
            fastVault: FastVaultService.shared,
            tierResolver: VultTierService(),
            mayachainService: maya
        )
    }

    private func assertThrowsTradingHalted(
        _ body: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("Expected SwapError.tradingHalted", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? SwapError, .tradingHalted, file: file, line: line)
        }
    }

    // MARK: - Fixtures

    private func makeEVMQuote() -> EVMQuote {
        EVMQuote(dstAmount: "1", tx: EVMQuote.Transaction(from: "0xfrom", to: "0xto", data: "0x", value: "0", gasPrice: "0", gas: 0))
    }

    private var haltedArbInbound: Data {
        """
        [{"chain":"ARB","address":"a","halted":true,"global_trading_paused":false,
          "chain_trading_paused":true,"chain_lp_actions_paused":false,
          "gas_rate":"0","gas_rate_units":"u"}]
        """.data(using: .utf8)!
    }

    private var openArbInbound: Data {
        """
        [{"chain":"ARB","address":"a","halted":false,"global_trading_paused":false,
          "chain_trading_paused":false,"chain_lp_actions_paused":false,
          "gas_rate":"0","gas_rate_units":"u"}]
        """.data(using: .utf8)!
    }

    private func makeTransaction(quote: SwapQuote? = nil) -> SwapTransaction {
        let arb = makeCoin(.arbitrum, ticker: "ARB")
        let eth = makeCoin(.ethereum, ticker: "ETH")
        return SwapTransaction(
            fromCoin: arb,
            toCoin: eth,
            fromAmount: 1,
            quote: quote ?? .mayachain(makeQuote()),
            gas: .zero,
            gasLimit: .zero,
            thorchainFee: .zero,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: arb,
            advancedSettings: .default
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String) -> Coin {
        let meta = CoinMeta.make(chain: chain, ticker: ticker, decimals: 18, isNativeToken: true)
        return Coin(asset: meta, address: "addr-\(ticker)", hexPublicKey: "")
    }

    private func makeQuote() -> ThorchainSwapQuote {
        ThorchainSwapQuote(
            dustThreshold: nil,
            expectedAmountOut: "0",
            expiry: 0,
            fees: Fees(affiliate: "0", asset: "CACAO", outbound: "0", total: "0", liquidity: nil, slippageBps: nil, totalBps: nil),
            inboundAddress: nil,
            inboundConfirmationBlocks: nil,
            inboundConfirmationSeconds: nil,
            memo: "memo",
            notes: "",
            outboundDelayBlocks: 0,
            outboundDelaySeconds: 0,
            recommendedMinAmountIn: "0",
            slippageBps: nil,
            totalSwapSeconds: nil,
            warning: "",
            router: nil,
            maxStreamingQuantity: nil
        )
    }
}

// swiftlint:disable async_without_await unused_parameter
/// Minimal `SwapInteractor` that only stubs the halt gate, for the VM-delegation
/// tests. Every other method is unreachable in those tests.
private struct StubGateInteractor: SwapInteractor {
    let throwError: Error?

    func fetchQuote(amount: Decimal, fromCoin: Coin, toCoin: Coin, vault: Vault, referredCode: String, slippageBps: Int?, recipientAddress: String?) async throws -> SwapQuoteResult? { nil }
    func fetchChainSpecific(fromCoin: Coin, toCoin: Coin, fromAmount: Decimal, quote: SwapQuote?) async throws -> BlockChainSpecific {
        .Cosmos(accountNumber: 0, sequence: 0, gas: 0, transactionType: 0, ibcDenomTrace: nil, gasLimit: nil)
    }
    func computeThorchainFee(chainSpecific: BlockChainSpecific, fromCoin: Coin, fromAmount: Decimal, vault: Vault) async throws -> BigInt { .zero }
    func assertSourceChainNotHalted(transaction: SwapTransaction) async throws {
        if let throwError { throw throwError }
    }
    func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async throws -> KeysignPayload { throw CancellationError() }
    func updateBalance(for coin: Coin) async {}
    func warmDiscountTier(for vault: Vault) async {}
}
// swiftlint:enable async_without_await unused_parameter

private actor PathStubClient: HTTPClientProtocol {
    private let responses: [String: Data]
    private(set) var requestCount = 0
    init(responses: [String: Data]) { self.responses = responses }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        await Task.yield()
        requestCount += 1
        guard let data = responses[target.path] else {
            throw HTTPError.statusCode(501, nil)
        }
        let url = target.baseURL.appendingPathComponent(target.path)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: data, response: response)
    }
}
