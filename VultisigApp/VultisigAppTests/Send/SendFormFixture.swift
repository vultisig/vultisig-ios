//
//  SendFormFixture.swift
//  VultisigAppTests
//
//  Test fixture helpers for `SendDetailsViewModel`. Construct a valid VM
//  state with sensible defaults; tests override the bits they care about.
//

import BigInt
import Foundation
@testable import VultisigApp

enum SendFormFixture {
    /// Build a `SendDetailsViewModel` with the given coin/vault pair and
    /// a mock interactor. Apply per-test overrides via the closure.
    @MainActor
    static func make(
        coin: Coin = makeBTC(),
        vault: Vault = makeVault(),
        interactor: SendInteractor? = nil,
        addressResolver: @escaping (String, Chain) async throws -> String = AddressService.resolveInput,
        destinationTagRequirementProvider: ((String) async -> RippleDestinationTagRequirement)? = nil,
        rippleService: RippleService = .shared,
        overrides: (SendDetailsViewModel) -> Void = { _ in }
    ) -> SendDetailsViewModel {
        let vm = SendDetailsViewModel(
            coin: coin,
            vault: vault,
            interactor: interactor ?? MockSendInteractor(),
            addressResolver: addressResolver,
            destinationTagRequirementProvider: destinationTagRequirementProvider,
            rippleService: rippleService
        )
        overrides(vm)
        return vm
    }

    // MARK: - Coin builders

    static func makeCoin(
        _ chain: Chain,
        ticker: String,
        decimals: Int,
        isNative: Bool,
        rawBalance: String = "0"
    ) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = rawBalance
        return coin
    }

    static func makeBTC(rawBalance: String = "100000000") -> Coin {
        makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: rawBalance)
    }

    static func makeETH(rawBalance: String = "1000000000000000000") -> Coin {
        makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true, rawBalance: rawBalance)
    }

    static func makeUSDC(rawBalance: String = "1000000000") -> Coin {
        makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false, rawBalance: rawBalance)
    }

    static func makeATOM(rawBalance: String = "10000000") -> Coin {
        makeCoin(.gaiaChain, ticker: "ATOM", decimals: 6, isNative: true, rawBalance: rawBalance)
    }

    static func makeTRX(rawBalance: String = "1000000") -> Coin {
        makeCoin(.tron, ticker: "TRX", decimals: 6, isNative: true, rawBalance: rawBalance)
    }

    static func makeXRP(rawBalance: String = "20000000") -> Coin {
        makeCoin(.ripple, ticker: "XRP", decimals: 6, isNative: true, rawBalance: rawBalance)
    }

    // MARK: - Vault builders

    /// Lightweight vault for tests that don't need SwiftData (most form-VM
    /// tests). Holds a localPartyID + empty coin list by default; pass
    /// `localPartyID: "server-..."` to exercise the Phase D fast-vault check.
    static func makeVault(
        localPartyID: String = "test-device-123",
        coins: [Coin] = []
    ) -> Vault {
        let vault = Vault(name: "test-vault")
        vault.localPartyID = localPartyID
        vault.pubKeyECDSA = "test-pub-ecdsa"
        vault.pubKeyEdDSA = "test-pub-eddsa"
        vault.hexChainCode = "abcd1234"
        vault.coins = coins
        return vault
    }
}
