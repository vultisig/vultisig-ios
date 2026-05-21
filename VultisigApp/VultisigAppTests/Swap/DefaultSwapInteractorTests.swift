//
//  DefaultSwapInteractorTests.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class DefaultSwapInteractorTests: XCTestCase {

    // MARK: - fetchQuote guards
    // Note: FastVault eligibility moved off the interactor — now lives on
    // `Vault.fastVaultEligibility` populated by `FastVaultEligibilityRefresher`.
    // See `FastVaultEligibilityRefresherTests` for the eligibility logic tests.

    func testFetchQuoteReturnsNilForZeroAmount() async throws {
        let quoteService = MockQuoteService(stubbedResult: .failure(StubError.shouldNotBeCalled))
        let interactor = makeInteractor(quote: quoteService)

        let result = try await interactor.fetchQuote(
            amount: 0,
            fromCoin: .example,
            toCoin: .example,
            vault: makeVault(),
            referredCode: ""
        )

        XCTAssertNil(result)
        XCTAssertEqual(quoteService.fetchQuoteCallCount, 0, "Quote service must not be hit when amount is zero")
    }

    func testFetchQuoteThrowsSameAssetWhenFromEqualsTo() async {
        let quoteService = MockQuoteService(stubbedResult: .failure(StubError.shouldNotBeCalled))
        let interactor = makeInteractor(quote: quoteService)
        let btc = makeCoin(.bitcoin, ticker: "BTC")

        do {
            _ = try await interactor.fetchQuote(
                amount: 1,
                fromCoin: btc,
                toCoin: btc,
                vault: makeVault(),
                referredCode: ""
            )
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(error as? SwapCryptoLogic.Errors, .sameAsset)
        }
        XCTAssertEqual(quoteService.fetchQuoteCallCount, 0)
    }

    // MARK: - fetchChainSpecific

    func testFetchChainSpecificDelegatesToBlockchainService() async throws {
        let blockchain = MockBlockChainService(
            stubbedResult: .success(.Cosmos(accountNumber: 7, sequence: 1, gas: 200_000, transactionType: 0, ibcDenomTrace: nil))
        )
        let interactor = makeInteractor(blockchain: blockchain)

        let result = try await interactor.fetchChainSpecific(
            fromCoin: .example,
            toCoin: .example,
            fromAmount: 0.1,
            quote: nil
        )

        XCTAssertEqual(blockchain.fetchSwapCallCount, 1)
        XCTAssertEqual(blockchain.lastFromAmount, 0.1)
        if case let .Cosmos(account, _, _, _, _) = result {
            XCTAssertEqual(account, 7)
        } else {
            XCTFail("Unexpected variant")
        }
    }

    func testFetchChainSpecificPropagatesError() async {
        let blockchain = MockBlockChainService(stubbedResult: .failure(StubError.networkError))
        let interactor = makeInteractor(blockchain: blockchain)

        do {
            _ = try await interactor.fetchChainSpecific(
                fromCoin: .example,
                toCoin: .example,
                fromAmount: 0,
                quote: nil
            )
            XCTFail("Expected throw")
        } catch {
            XCTAssertEqual(error as? StubError, .networkError)
        }
    }

    // MARK: - updateBalance

    func testUpdateBalanceDelegatesToBalanceService() async {
        let balance = MockBalanceService()
        let interactor = makeInteractor(balance: balance)
        let coin = makeCoin(.ethereum, ticker: "ETH")

        await interactor.updateBalance(for: coin)

        XCTAssertEqual(balance.updateBalanceCallCount, 1)
        XCTAssertEqual(balance.lastUpdatedCoin, coin)
    }

    // MARK: - Fixtures

    private func makeInteractor(
        quote: QuoteServiceProtocol = MockQuoteService(stubbedResult: .failure(StubError.shouldNotBeCalled)),
        blockchain: BlockChainServiceProtocol = MockBlockChainService(stubbedResult: .failure(StubError.shouldNotBeCalled)),
        balance: BalanceServiceProtocol = MockBalanceService(),
        fastVault: FastVaultServiceProtocol = MockFastVaultService()
    ) -> DefaultSwapInteractor {
        DefaultSwapInteractor(
            quote: quote,
            blockchain: blockchain,
            balance: balance,
            fastVault: fastVault
        )
    }

    private func makeVault(localPartyID: String = "iPhone-12345") -> Vault {
        Vault(
            name: "Test Vault",
            signers: [],
            pubKeyECDSA: "test-pub-ecdsa",
            pubKeyEdDSA: "test-pub-eddsa",
            keyshares: [],
            localPartyID: localPartyID,
            hexChainCode: "hex",
            resharePrefix: nil,
            libType: .DKLS
        )
    }

    private func makeCoin(_ chain: Chain, ticker: String) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: 8)
        return Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
    }
}

private enum StubError: Error, Equatable {
    case shouldNotBeCalled
    case networkError
}
