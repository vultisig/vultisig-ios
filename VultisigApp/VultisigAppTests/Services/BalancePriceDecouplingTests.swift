//
//  BalancePriceDecouplingTests.swift
//  VultisigAppTests
//
//  Covers decoupling price fetching from balance fetching: prices and balances
//  run concurrently, a failing/slow price endpoint never blocks the balance
//  flow, currency changes take a rates-only path (no balance RPCs), and warm
//  starts never render a misleading "$0.00" fiat frame.
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class BalancePriceDecouplingTests: XCTestCase {
    private var storeToken: TestContextToken!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    // MARK: - Test double

    /// Records calls and can optionally throw or gate (block until released) so a
    /// test can observe ordering deterministically without the network.
    private final class FakeCryptoPriceService: CryptoPriceServiceProtocol, @unchecked Sendable {
        private(set) var fetchPricesCoinsCallCount = 0
        private(set) var fetchPriceCoinCallCount = 0
        var errorToThrow: Error?
        var onEnter: (() -> Void)?

        // `lock` guards the gate state so `release()` is safe whether it runs
        // before or after the continuation is suspended (no deadlock either way).
        private let lock = NSLock()
        private var gateEnabled = false
        private var released = false
        private var gateContinuation: CheckedContinuation<Void, Never>?

        func enableGate() { gateEnabled = true }

        func release() {
            lock.lock()
            if let continuation = gateContinuation {
                gateContinuation = nil
                lock.unlock()
                continuation.resume()
            } else {
                released = true
                lock.unlock()
            }
        }

        func fetchPrices(coins _: [CoinMeta]) async throws {
            fetchPricesCoinsCallCount += 1
            onEnter?()
            if gateEnabled {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.lock()
                    if released {
                        lock.unlock()
                        continuation.resume()
                    } else {
                        gateContinuation = continuation
                        lock.unlock()
                    }
                }
            }
            if let errorToThrow { throw errorToThrow }
        }

        // swiftlint:disable:next async_without_await
        func fetchPrice(coin _: Coin) async throws {
            fetchPriceCoinCallCount += 1
            if let errorToThrow { throw errorToThrow }
        }
    }

    private final class BoolBox: @unchecked Sendable {
        var value = false
    }

    // MARK: - AC#1: balances begin without waiting for fetchPrices

    func test_updateBalances_runsBalancePhasesWhilePricesStillPending() async {
        // A gated price service blocks indefinitely until released. If balances
        // were still gated behind prices, the balance phases (Phase 2 + Phase 3)
        // could never run. With decoupling they complete and `updateBalances`
        // only parks on the final `await pricesDone`.
        let fake = FakeCryptoPriceService()
        fake.enableGate()
        let sut = BalanceService(cryptoPriceService: fake)
        let vault = TestStore.makeVault()

        let entered = expectation(description: "price fetch launched concurrently")
        fake.onEnter = { entered.fulfill() }

        let didFinish = BoolBox()
        let task = Task {
            await sut.updateBalances(vault: vault)
            didFinish.value = true
        }

        await fulfillment(of: [entered], timeout: 2)

        // The price fetch is still gated, so updateBalances must not have returned.
        XCTAssertFalse(
            didFinish.value,
            "updateBalances must reach the balance phases and await prices, not return before prices resolve"
        )

        fake.release()
        _ = await task.value
        XCTAssertTrue(didFinish.value)
        XCTAssertEqual(fake.fetchPricesCoinsCallCount, 1)
    }

    // MARK: - AC#2: slow/failing price endpoint does not delay balance display

    func test_updateBalances_failingPriceService_completesAndIsNotPropagated() async {
        // A thrown price error must be swallowed; updateBalances must still return
        // (a hang would time the test out) without propagating the error.
        let fake = FakeCryptoPriceService()
        fake.errorToThrow = URLError(.timedOut)
        let sut = BalanceService(cryptoPriceService: fake)
        let vault = TestStore.makeVault()

        await sut.updateBalances(vault: vault)

        XCTAssertEqual(fake.fetchPricesCoinsCallCount, 1)
    }

    // MARK: - AC#3: currency change is rates-only (no per-coin balance RPCs)

    func test_refreshRates_fetchesRatesAndDoesNotMutateBalances() async {
        let fake = FakeCryptoPriceService()
        let sut = BalanceService(cryptoPriceService: fake)
        let vault = TestStore.makeVault()

        let coin = Coin(
            asset: CoinMeta.make(chain: .bitcoin, ticker: "BTC", decimals: 8),
            address: "bc1qtest",
            hexPublicKey: ""
        )
        coin.rawBalance = "12345"
        vault.coins = [coin]

        await sut.refreshRates(vault: vault)

        XCTAssertEqual(fake.fetchPricesCoinsCallCount, 1, "currency change must fetch rates")
        XCTAssertEqual(fake.fetchPriceCoinCallCount, 0)
        XCTAssertEqual(
            coin.rawBalance,
            "12345",
            "refreshRates must not issue balance RPCs or mutate persisted balances"
        )
    }

    // MARK: - AC#4: no persistent $0-fiat on warm start (and cold-start guard)

    func test_warmStartWithCachedRate_rendersFiatNotPlaceholder() throws {
        let providerId = "btc-warm-\(UUID().uuidString)"
        let coin = Coin(
            asset: CoinMeta(
                chain: .bitcoin,
                ticker: "BTC",
                logo: "btc",
                decimals: 8,
                priceProviderId: providerId,
                contractAddress: "",
                isNativeToken: true
            ),
            address: "bc1qtest",
            hexPublicKey: ""
        )
        coin.rawBalance = "100000000" // 1 BTC

        try RateProvider.shared.save(rates: [
            Rate(fiat: SettingsCurrency.current.rawValue, crypto: providerId, value: 50_000)
        ])

        XCTAssertTrue(coin.fiatRateAvailable)
        XCTAssertNotEqual(coin.balanceInFiatDecimal, .zero)
        XCTAssertNotEqual(coin.balanceInFiatForDisplay, String.fiatPlaceholder)
    }

    func test_coldStartNonZeroBalanceNoRate_rendersPlaceholderNotZeroFiat() {
        let coin = Coin(
            asset: CoinMeta(
                chain: .bitcoin,
                ticker: "BTC",
                logo: "btc",
                decimals: 8,
                priceProviderId: "btc-cold-\(UUID().uuidString)",
                contractAddress: "",
                isNativeToken: true
            ),
            address: "bc1qtest",
            hexPublicKey: ""
        )
        coin.rawBalance = "100000000" // 1 BTC, but no rate cached

        XCTAssertFalse(coin.fiatRateAvailable)
        XCTAssertEqual(coin.balanceInFiatForDisplay, String.fiatPlaceholder)
    }

    func test_zeroBalanceNoRate_rendersFiatNotPlaceholder() {
        // A zero crypto balance has no misleading-fiat problem — "$0.00" is correct.
        let coin = Coin(
            asset: CoinMeta(
                chain: .bitcoin,
                ticker: "BTC",
                logo: "btc",
                decimals: 8,
                priceProviderId: "btc-zero-\(UUID().uuidString)",
                contractAddress: "",
                isNativeToken: true
            ),
            address: "bc1qtest",
            hexPublicKey: ""
        )
        coin.rawBalance = "0"

        XCTAssertNotEqual(coin.balanceInFiatForDisplay, String.fiatPlaceholder)
    }
}
