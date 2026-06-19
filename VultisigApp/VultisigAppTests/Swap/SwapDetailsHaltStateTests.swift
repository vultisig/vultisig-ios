//
//  SwapDetailsHaltStateTests.swift
//  VultisigAppTests
//
//  Screen-level halt state (PR-5): a halted Maya inbound chain is reflected in
//  the view model's haltedChains / isCurrentRouteHalted. THORChain inbound is
//  fail-soft (its client isn't injectable in unit tests → empty), so the Maya
//  path stands in for the shared SwapHaltGate behaviour the screen consumes.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class SwapDetailsHaltStateTests: XCTestCase {

    func testRefreshHaltedChainsFlagsHaltedMayaChain() async throws {
        let mayaInbound = """
        [
          {"chain":"ARB","address":"a","halted":true,"global_trading_paused":false,
           "chain_trading_paused":true,"chain_lp_actions_paused":false,
           "gas_rate":"0","gas_rate_units":"u"}
        ]
        """.data(using: .utf8)!

        let maya = MayachainService(httpClient: PathStubClient(responses: [
            "/mayachain/inbound_addresses": mayaInbound
        ]))
        let vm = SwapDetailsViewModel(
            interactor: NoopInteractor(),
            mayachainService: maya
        )

        let arb = makeCoin(.arbitrum, ticker: "ARB")
        await vm.refreshHaltedChains(coins: [arb])

        XCTAssertTrue(vm.haltedChains.contains(.arbitrum))

        vm.fromCoin = arb
        vm.toCoin = makeCoin(.ethereum, ticker: "ETH")
        XCTAssertTrue(vm.isCurrentRouteHalted, "A halted source chain must mark the route halted")
    }

    func testNonHaltedRouteIsNotFlagged() async throws {
        let mayaInbound = """
        [
          {"chain":"ARB","address":"a","halted":false,"global_trading_paused":false,
           "chain_trading_paused":false,"chain_lp_actions_paused":false,
           "gas_rate":"0","gas_rate_units":"u"}
        ]
        """.data(using: .utf8)!

        let maya = MayachainService(httpClient: PathStubClient(responses: [
            "/mayachain/inbound_addresses": mayaInbound
        ]))
        let vm = SwapDetailsViewModel(interactor: NoopInteractor(), mayachainService: maya)

        let arb = makeCoin(.arbitrum, ticker: "ARB")
        await vm.refreshHaltedChains(coins: [arb])
        vm.fromCoin = arb
        vm.toCoin = makeCoin(.ethereum, ticker: "ETH")
        XCTAssertFalse(vm.isCurrentRouteHalted)
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, ticker: String) -> Coin {
        let meta = CoinMeta.make(chain: chain, ticker: ticker, decimals: 18, isNativeToken: true)
        return Coin(asset: meta, address: "addr-\(ticker)", hexPublicKey: "")
    }
}

private actor PathStubClient: HTTPClientProtocol {
    private let responses: [String: Data]
    init(responses: [String: Data]) { self.responses = responses }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        await Task.yield()
        guard let data = responses[target.path] else {
            throw HTTPError.statusCode(501, nil)
        }
        let url = target.baseURL.appendingPathComponent(target.path)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: data, response: response)
    }
}

// swiftlint:disable async_without_await unused_parameter
@MainActor
private final class NoopInteractor: SwapInteractor {
    func fetchQuote(amount: Decimal, fromCoin: Coin, toCoin: Coin, vault: Vault, referredCode: String) async throws -> SwapQuoteResult? { nil }
    func isProviderSelectionUnlocked(for vault: Vault) async -> Bool { false }
    func fetchChainSpecific(fromCoin: Coin, toCoin: Coin, fromAmount: Decimal, quote: SwapQuote?) async throws -> BlockChainSpecific {
        .Cosmos(accountNumber: 0, sequence: 0, gas: 0, transactionType: 0, ibcDenomTrace: nil)
    }
    func computeThorchainFee(chainSpecific: BlockChainSpecific, fromCoin: Coin, fromAmount: Decimal, vault: Vault) async throws -> BigInt { .zero }
    func buildSwapKeysignPayload(transaction: SwapTransaction, vault: Vault) async throws -> KeysignPayload { throw CancellationError() }
    func warmDiscountTier(for vault: Vault) async {}
    func updateBalance(for coin: Coin) async {}
}
// swiftlint:enable async_without_await unused_parameter
