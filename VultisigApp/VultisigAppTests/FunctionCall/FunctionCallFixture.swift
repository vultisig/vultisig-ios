//
//  FunctionCallFixture.swift
//  VultisigAppTests
//
//  Shared test fixture helpers for the rewritten FunctionCall sub-models.
//  Mirrors `SendFormFixture` — constructs coins / vaults / canonical inputs
//  so sub-model tests can focus on the migration-specific assertions
//  (memo encoding, transaction-type wiring, address-validation regression,
//  `toSendTransaction` output).
//

import BigInt
import Foundation
@testable import VultisigApp

enum FunctionCallFixture {

    // MARK: - Vault

    /// Build a vault that holds the canonical RUNE coin plus any
    /// additional coins requested. The RUNE coin gets a stable address so
    /// address-prefill paths produce deterministic memos in pin tests.
    static func makeVault(
        coins: [Coin]? = nil,
        localPartyID: String = "test-device-fc"
    ) -> Vault {
        let vault = Vault(name: "test-vault-fc")
        vault.localPartyID = localPartyID
        vault.pubKeyECDSA = "test-pub-ecdsa"
        vault.pubKeyEdDSA = "test-pub-eddsa"
        vault.hexChainCode = "abcd1234"
        vault.coins = coins ?? [makeRUNE(), makeATOM()]
        return vault
    }

    // MARK: - Coin builders

    static func makeCoin(
        _ chain: Chain,
        ticker: String,
        decimals: Int,
        isNative: Bool,
        rawBalance: String = "100000000",
        address: String? = nil
    ) -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        let coin = Coin(asset: asset, address: address ?? "test-addr-\(ticker)", hexPublicKey: "")
        coin.rawBalance = rawBalance
        return coin
    }

    static func makeRUNE(rawBalance: String = "100000000000") -> Coin {
        makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true, rawBalance: rawBalance, address: thorAddress)
    }

    static func makeRUJI(rawBalance: String = "500000000") -> Coin {
        makeCoin(.thorChain, ticker: "RUJI", decimals: 8, isNative: false, rawBalance: rawBalance, address: thorAddress)
    }

    static func makeTCY(rawBalance: String = "1000000000") -> Coin {
        makeCoin(.thorChain, ticker: "TCY", decimals: 8, isNative: false, rawBalance: rawBalance, address: thorAddress)
    }

    static func makeATOM(rawBalance: String = "10000000") -> Coin {
        makeCoin(.gaiaChain, ticker: "ATOM", decimals: 6, isNative: true, rawBalance: rawBalance, address: cosmosAddress)
    }

    static func makeKUJI(rawBalance: String = "10000000") -> Coin {
        makeCoin(.kujira, ticker: "KUJI", decimals: 6, isNative: true, rawBalance: rawBalance, address: kujiAddress)
    }

    static func makeBTC(rawBalance: String = "100000000") -> Coin {
        makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true, rawBalance: rawBalance, address: btcAddress)
    }

    // MARK: - Canonical addresses (deterministic memo strings)

    static let thorAddress = "thor1xyzfixturethorvaultaddress00000000000000"
    static let mayaAddress = "maya1xyzfixturemayachainnodeaddress0000000000"
    static let cosmosAddress = "cosmos1xyzfixturegaiachainvaultaddress000000000"
    static let kujiAddress = "kujira1xyzfixturekujirachainvaultaddress00000"
    static let tonAddress = "UQAfixturetonchainvaultaddress00000000000000000"
    static let btcAddress = "bc1qfixturebtcvaultaddress00000000000"
    static let nodeAddress = "thor1validatorfixturenodeaddress0000000000000"
    static let newNodeAddress = "thor1newvalidatorfixturenodeaddress0000000000"
}
