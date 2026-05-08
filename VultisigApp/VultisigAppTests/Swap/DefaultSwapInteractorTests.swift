//
//  DefaultSwapInteractorTests.swift
//  VultisigAppTests
//
//  Coverage for the parts of `DefaultSwapInteractor` that don't go through
//  VultTierService (which today reads BalanceService.shared + on-chain
//  contracts and isn't behind a protocol seam yet). The fetchQuote happy
//  path is covered indirectly via the §4 VM tests against a mock interactor.
//

import BigInt
import XCTest
@testable import VultisigApp

@MainActor
final class DefaultSwapInteractorTests: XCTestCase {

    // MARK: - loadFastVault

    func testLoadFastVaultReturnsTrueWhenServerExistsAndPartyIsRemote() async {
        let fastVault = MockFastVaultService()
        fastVault.stubbedExist = true
        let interactor = makeInteractor(fastVault: fastVault)

        let vault = makeVault(localPartyID: "iPhone-12345")
        let result = await interactor.loadFastVault(vault: vault)

        XCTAssertTrue(result)
        XCTAssertEqual(fastVault.existCallCount, 1)
        XCTAssertEqual(fastVault.lastQueriedPubKey, vault.pubKeyECDSA)
    }

    func testLoadFastVaultReturnsFalseForServerPrefixLocalParty() async {
        let fastVault = MockFastVaultService()
        fastVault.stubbedExist = true
        let interactor = makeInteractor(fastVault: fastVault)

        // Server-prefixed localPartyID indicates the FastVault peer was a local backup —
        // not a remote signer. Treated as not-fast-vault.
        let vault = makeVault(localPartyID: "Server-12345")
        let result = await interactor.loadFastVault(vault: vault)

        XCTAssertFalse(result)
    }

    func testLoadFastVaultReturnsFalseWhenServerDoesNotExist() async {
        let fastVault = MockFastVaultService()
        fastVault.stubbedExist = false
        let interactor = makeInteractor(fastVault: fastVault)

        let result = await interactor.loadFastVault(vault: makeVault())
        XCTAssertFalse(result)
    }

    // MARK: - fetchQuote guards

    func testFetchQuoteReturnsNilForZeroAmount() async throws {
        let quoteService = MockQuoteService(stubbedResult: .failure(StubError.shouldNotBeCalled))
        let interactor = makeInteractor(quote: quoteService)

        var draft = SwapDraft()
        draft.fromAmount = ""

        let result = try await interactor.fetchQuote(draft: draft, vault: makeVault(), referredCode: "")

        XCTAssertNil(result)
        XCTAssertEqual(quoteService.fetchQuoteCallCount, 0, "Quote service must not be hit when amount is zero")
    }

    func testFetchQuoteThrowsSameAssetWhenFromEqualsTo() async {
        let quoteService = MockQuoteService(stubbedResult: .failure(StubError.shouldNotBeCalled))
        let interactor = makeInteractor(quote: quoteService)

        var draft = SwapDraft()
        draft.fromCoin = makeCoin(.bitcoin, ticker: "BTC")
        draft.toCoin = draft.fromCoin
        draft.fromAmount = "1.0"

        do {
            _ = try await interactor.fetchQuote(draft: draft, vault: makeVault(), referredCode: "")
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

        var draft = SwapDraft()
        draft.fromAmount = "0.1"
        let result = try await interactor.fetchChainSpecific(draft: draft)

        XCTAssertEqual(blockchain.fetchSwapCallCount, 1)
        XCTAssertEqual(blockchain.lastDraft, draft)
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
            _ = try await interactor.fetchChainSpecific(draft: SwapDraft())
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
