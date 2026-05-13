//
//  SendTransactionTests.swift
//  VultisigAppTests
//
//  Coverage for the new immutable `struct SendTransaction` — empty seed,
//  with(...) builder behaviour, and the three pilot decisions baked in.
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendTransactionTests: XCTestCase {

    // MARK: - empty seed

    func testEmptySeedDefaultsAreZeroOrEmpty() throws {
        let vault = try TestStore.makeVault()
        let coin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        let tx = SendTransaction.empty(coin: coin, vault: vault)

        XCTAssertEqual(tx.toAddress, "")
        XCTAssertEqual(tx.amount, "")
        XCTAssertEqual(tx.memo, "")
        XCTAssertEqual(tx.gas, .zero)
        XCTAssertEqual(tx.fee, .zero)
        XCTAssertEqual(tx.feeMode, .default)
        XCTAssertFalse(tx.sendMaxAmount)
        XCTAssertFalse(tx.isFastVault)
        XCTAssertNil(tx.customGasLimit)
        XCTAssertNil(tx.customByteFee)
        XCTAssertTrue(tx.memoFunctionDictionary.isEmpty)
    }

    func testEmptySeedFromAddressMirrorsCoinAddress() throws {
        let vault = try TestStore.makeVault()
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let tx = SendTransaction.empty(coin: coin, vault: vault)
        XCTAssertEqual(tx.fromAddress, coin.address)
    }

    // MARK: - Decision 1: plain [String: String] dictionary

    func testMemoFunctionDictionaryIsPlainDict() throws {
        let vault = try TestStore.makeVault()
        let coin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        let tx = SendTransaction.empty(coin: coin, vault: vault)
        // Type assertion: not a ThreadSafeDictionary — directly subscriptable.
        XCTAssertNil(tx.memoFunctionDictionary["pool"])
    }

    // MARK: - Decision 2: vault required (non-optional)

    func testVaultIsNonOptional() throws {
        // If the type system enforces non-optional, this just compiles. Belt-and-
        // braces: read .vault and verify it isn't nil at runtime.
        let vault = try TestStore.makeVault()
        let coin = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        let tx = SendTransaction.empty(coin: coin, vault: vault)
        XCTAssertEqual(tx.vault.pubKeyECDSA, vault.pubKeyECDSA)
    }

    // MARK: - feeCoin resolution

    func testFeeCoinForNativeSourceIsSelf() throws {
        let vault = try TestStore.makeVault()
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let tx = SendTransaction.empty(coin: eth, vault: vault)
        XCTAssertEqual(tx.feeCoin, eth)
    }

    func testFeeCoinForERC20FallsBackToCoinWhenVaultHasNoNative() throws {
        let vault = try TestStore.makeVault()
        let usdc = makeCoin(.ethereum, ticker: "USDC", decimals: 6, isNative: false)
        let tx = SendTransaction.empty(coin: usdc, vault: vault)
        // Empty vault — no ETH sibling — falls back to coin.
        XCTAssertEqual(tx.feeCoin, usdc)
    }

    // MARK: - Builder

    func testWithUpdatesGasAndFeePreservingIdentity() throws {
        let vault = try TestStore.makeVault()
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let original = SendTransaction.empty(coin: coin, vault: vault)
        let updated = original.with(gas: BigInt(50_000_000_000), fee: BigInt(1_500_000_000_000_000))
        XCTAssertEqual(updated.gas, BigInt(50_000_000_000))
        XCTAssertEqual(updated.fee, BigInt(1_500_000_000_000_000))
        XCTAssertEqual(updated.coin, original.coin) // identity preserved
        XCTAssertEqual(updated.fromAddress, original.fromAddress)
    }

    // MARK: - Decision 3: with(...) preserves custom gas pin

    func testWithDoesNotClearCustomGasLimitOnRefresh() throws {
        let vault = try TestStore.makeVault()
        let coin = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true)
        let pinned = SendTransaction(
            coin: coin,
            vault: vault,
            fromAddress: coin.address,
            toAddress: "to",
            toAddressLabel: nil,
            amount: "0.5",
            amountInFiat: "",
            memo: "",
            gas: BigInt(20_000_000_000),
            fee: .zero,
            feeMode: .fast,
            estimatedGasLimit: BigInt(21_000),
            customGasLimit: BigInt(50_000), // user pinned
            customByteFee: nil,
            sendMaxAmount: false,
            isFastVault: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin
        )
        // Refresh path: re-fetched gas + fee but the pinned custom limit must stick.
        let refreshed = pinned.with(gas: BigInt(30_000_000_000), fee: BigInt(630_000_000_000_000))
        XCTAssertEqual(refreshed.customGasLimit, BigInt(50_000)) // preserved
        XCTAssertEqual(refreshed.gas, BigInt(30_000_000_000))     // updated
        XCTAssertEqual(refreshed.gasLimit, BigInt(50_000))        // custom wins over estimated
    }

    func testWithDoesNotClearCustomByteFeeOnRefresh() throws {
        let vault = try TestStore.makeVault()
        let btc = makeCoin(.bitcoin, ticker: "BTC", decimals: 8, isNative: true)
        let pinned = SendTransaction(
            coin: btc,
            vault: vault,
            fromAddress: btc.address,
            toAddress: "to",
            toAddressLabel: nil,
            amount: "0.1",
            amountInFiat: "",
            memo: "",
            gas: BigInt(50),
            fee: BigInt(5_000),
            feeMode: .fast,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: BigInt(80),
            sendMaxAmount: false,
            isFastVault: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: btc
        )
        let refreshed = pinned.with(gas: BigInt(60), fee: BigInt(6_000))
        XCTAssertEqual(refreshed.customByteFee, BigInt(80))
        XCTAssertEqual(refreshed.byteFee, BigInt(80)) // custom wins
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, rawBalance: String = "0") -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = rawBalance
        return coin
    }
}
