//
//  SwapVerifyHaltGateTests.swift
//  VultisigAppTests
//
//  Sign-time halt block (PR-4, HIGH security): the pre-flight re-check bypasses
//  the inbound cache and blocks signing when the source chain is halted. The
//  Maya inbound client is injectable, so it stands in for the source-chain
//  re-check the verify path performs across both protocols.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapVerifyHaltGateTests: XCTestCase {

    func testHaltedSourceChainBlocksSigning() async {
        let vm = makeVM(mayaInbound: haltedArbInbound)
        let safe = await vm.isSourceChainSafeToSign()
        XCTAssertFalse(safe, "A halted source chain must block signing")
        XCTAssertEqual((vm.error as? SwapError), .tradingHalted)
    }

    func testNonHaltedSourceChainProceeds() async {
        let vm = makeVM(mayaInbound: openArbInbound)
        let safe = await vm.isSourceChainSafeToSign()
        XCTAssertTrue(safe, "A non-halted source chain must allow signing")
        XCTAssertNil(vm.error)
    }

    func testHaltReCheckBypassesCache() async {
        // The sign-time fetch must issue a fresh request every time (bypassCache)
        // rather than serving a stale cached entry.
        let stub = PathStubClient(responses: ["/mayachain/inbound_addresses": haltedArbInbound])
        let maya = MayachainService(httpClient: stub)
        let vm = makeVM(maya: maya)
        _ = await vm.isSourceChainSafeToSign()
        _ = await vm.isSourceChainSafeToSign()
        let count = await stub.requestCount
        XCTAssertEqual(count, 2, "Each sign-time re-check must bypass the cache and refetch")
    }

    // MARK: - Thread #4: aggregator routes skip the preflight

    func testAggregatorRouteSkipsPreflightEvenOnHaltedChain() async {
        // Even though the source chain's Maya inbound is halted, a 1inch route
        // never deposits there — the preflight is skipped and signing proceeds.
        let stub = PathStubClient(responses: ["/mayachain/inbound_addresses": haltedArbInbound])
        let maya = MayachainService(httpClient: stub)
        let vm = makeVM(maya: maya, quote: .oneinch(makeEVMQuote(), fee: nil))
        let safe = await vm.isSourceChainSafeToSign()
        XCTAssertTrue(safe, "Aggregator routes skip the native halt preflight")
        XCTAssertNil(vm.error)
        let count = await stub.requestCount
        XCTAssertEqual(count, 0, "Aggregator routes must not fetch any inbound")
    }

    // MARK: - Thread #6: native routes fail CLOSED on an unverifiable fetch

    func testNativeRouteFailsClosedWhenInboundFetchThrows() async {
        // The Maya inbound endpoint returns a 501 (no stubbed response) → the
        // throwing fetch propagates → the native route is BLOCKED, not allowed.
        let maya = MayachainService(httpClient: PathStubClient(responses: [:]))
        let vm = makeVM(maya: maya)
        let safe = await vm.isSourceChainSafeToSign()
        XCTAssertFalse(safe, "A native route must fail closed when the inbound re-check can't be verified")
        XCTAssertEqual((vm.error as? SwapError), .tradingHalted)
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

    private func makeVM(mayaInbound: Data) -> SwapVerifyViewModel {
        makeVM(maya: MayachainService(httpClient: PathStubClient(responses: ["/mayachain/inbound_addresses": mayaInbound])))
    }

    private func makeVM(maya: MayachainService, quote: SwapQuote? = nil) -> SwapVerifyViewModel {
        let arb = makeCoin(.arbitrum, ticker: "ARB")
        let eth = makeCoin(.ethereum, ticker: "ETH")
        let tx = SwapTransaction(
            fromCoin: arb,
            toCoin: eth,
            fromAmount: 1,
            quote: quote ?? .mayachain(makeQuote()),
            gas: .zero,
            thorchainFee: .zero,
            vultDiscountBps: 0,
            referralDiscountBps: 0,
            feeCoin: arb,
            advancedSettings: .default
        )
        return SwapVerifyViewModel(transaction: tx, mayachainService: maya)
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
