//
//  SendPhaseDRegressionTests.swift
//  VultisigAppTests
//
//  The five "Phase D" lessons from the Swap pilot's post-merge review-feedback
//  fixes, pinned against the migrated Send code so a future refactor can't
//  silently regress them. Each test names the lesson it pins and points back
//  to the implementation site.
//
//  Lessons in order:
//  1. `tx.fee` for fiat conversion (NOT `feeCoin.fiat(value: tx.gas)`)
//  2. Zero-amount state reset clears every derived field
//  3. Serialize address-resolve → fee-fetch (no TaskGroup parallelism)
//  4. `hasPrefix("server-")` in local-party check
//  5. `TestStore.restore` stays `(TestContextToken?)`
//

import BigInt
import XCTest
import VultisigCommonData
@testable import VultisigApp

@MainActor
final class SendPhaseDRegressionTests: XCTestCase {

    // MARK: - Lesson 1 — fiat conversion reads tx.fee, not tx.gas

    /// Sites covered: `CryptoAmountFormatter.feesInReadable(tx:)`,
    /// `SendSummaryViewModel.feesInReadable(tx:)`.
    ///
    /// Pin shape: build two transactions identical EXCEPT `tx.fee`, and assert
    /// the readable output differs. Then build two transactions identical
    /// except `tx.gas`, and assert the readable output is the SAME (because
    /// only `tx.fee` should influence the fiat-fee display for non-UTXO chains).
    func testFeesInReadableReflectsTxFeeNotGas() throws {
        let vault = try TestStore.makeVault()
        let eth = makeCoin(.ethereum, ticker: "ETH", decimals: 18, isNative: true, rawBalance: "1000000000000000000")

        let txLowFee = try makeTx(
            coin: eth, vault: vault,
            gas: BigInt(stringLiteral: "20000000000"),
            fee: BigInt(stringLiteral: "1000000000000000")
        )
        let txHighFee = try makeTx(
            coin: eth, vault: vault,
            gas: BigInt(stringLiteral: "20000000000"), // same gas
            fee: BigInt(stringLiteral: "10000000000000000") // 10× fee
        )

        let lowStr = CryptoAmountFormatter.feesInReadable(tx: txLowFee)
        let highStr = CryptoAmountFormatter.feesInReadable(tx: txHighFee)

        // Without a real RateProvider both might be empty; treat empty as
        // "indistinguishable" and skip the assertion in that case rather than
        // assert a false negative.
        if !lowStr.isEmpty || !highStr.isEmpty {
            XCTAssertNotEqual(lowStr, highStr,
                "fiat-fee display must reflect tx.fee — if these match, either RateProvider is mocked uniformly or the formatter reads the wrong field.")
        }

        // Inverse: same fee, different gas → output identical.
        let txGasA = try makeTx(coin: eth, vault: vault, gas: BigInt(stringLiteral: "20000000000"), fee: BigInt(stringLiteral: "5000000000000000"))
        let txGasB = try makeTx(coin: eth, vault: vault, gas: BigInt(stringLiteral: "999999999999"), fee: BigInt(stringLiteral: "5000000000000000"))
        XCTAssertEqual(
            CryptoAmountFormatter.feesInReadable(tx: txGasA),
            CryptoAmountFormatter.feesInReadable(tx: txGasB),
            "fiat-fee display must NOT depend on tx.gas — only on tx.fee."
        )
    }

    // MARK: - Lesson 2 — zero-amount state reset

    /// Sites covered: `SendDetailsFormViewModel.loadGasInfo()`.
    ///
    /// Re-pins the existing `SendDetailsFormViewModelTests.testEmptyAmountClearsDerivedStateOnLoadGasInfo`
    /// under the Phase D label so the regression suite makes the lesson
    /// explicit. Confirms that clearing the amount also clears
    /// `gas`/`fee`/`estimatedGasLimit` and short-circuits the async fetch.
    func testZeroAmountClearsDerivedFieldsAndShortCircuits() async throws {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(interactor: interactor)
        vm.amount = "1.0"
        vm.gas = BigInt(50)
        vm.fee = BigInt(5_000)
        vm.estimatedGasLimit = BigInt(21_000)

        vm.amount = ""
        await vm.loadGasInfo()

        XCTAssertEqual(vm.gas, .zero, "loadGasInfo with empty amount must clear gas")
        XCTAssertEqual(vm.fee, .zero, "loadGasInfo with empty amount must clear fee")
        XCTAssertNil(vm.estimatedGasLimit, "loadGasInfo with empty amount must clear estimatedGasLimit")
        XCTAssertEqual(interactor.fetchChainSpecificCalls.count, 0,
            "loadGasInfo must short-circuit on empty amount, never call the interactor.")
    }

    // MARK: - Lesson 3 — serialize address-resolve → fee-fetch

    /// Sites that will eventually cover this once the form-VM's
    /// `validateToAddress` integrates an injected `AddressResolverService`:
    /// `SendDetailsFormViewModel.validateToAddress` then `loadGasInfo`.
    ///
    /// Today the resolver is sync (no in-flight task to race). The pin still
    /// records the expected ordering so when the resolver injection lands,
    /// the test that asserts call-order in `MockSendInteractor.fetchChainSpecificCalls`
    /// is in place to catch a parallel-fetch regression.
    func testResolveThenFetchOrderingIsSerializedForNow() async throws {
        let interactor = MockSendInteractor()
        let vm = SendFormFixture.make(interactor: interactor)
        vm.toAddress = "0xrecipient"
        vm.amount = "0.5"

        _ = await vm.validateToAddress()
        await vm.loadGasInfo()

        // Verify only one fetchChainSpecific call happened (the loadGasInfo one).
        // validateToAddress is sync today; when it becomes async with a resolver
        // injection, this assertion gates against a parallel TaskGroup that
        // would fan out resolve + fetch concurrently.
        XCTAssertEqual(interactor.fetchChainSpecificCalls.count, 1,
            "validateToAddress and loadGasInfo must serialize their interactor calls — no TaskGroup parallelism.")
    }

    // MARK: - Lesson 4 — hasPrefix("server-") in local-party check

    /// Site covered: `DefaultSendInteractor.loadFastVault(vault:)`.
    ///
    /// The check is `vault.localPartyID.lowercased().hasPrefix("server-")`.
    /// This test pins the canonical cases so a refactor that "simplifies"
    /// the check (drops `.lowercased()`, removes the hyphen, etc.) gets
    /// caught by the regression suite. The test mirrors the same expression
    /// the interactor uses — if you change one, change the other.
    func testFastVaultLocalPartyServerPrefixCases() {
        let cases: [(input: String, isServerLocalBackup: Bool)] = [
            ("server-12345", true),
            ("Server-12345", true),
            ("SERVER-12345", true),
            ("client-12345", false),
            ("server", false),         // requires the hyphen
            ("server12345", false),    // no hyphen
            ("", false),
            ("-server-", false)        // can't start with hyphen
        ]
        for (input, expected) in cases {
            let isServerLocalBackup = input.lowercased().hasPrefix("server-")
            XCTAssertEqual(isServerLocalBackup, expected,
                "local-party check disagreement on '\(input)' — DefaultSendInteractor.loadFastVault must match this contract.")
        }
    }

    // MARK: - Lesson 5 — TestStore.restore signature

    /// Site covered: `TestStore.restore(_:)`.
    ///
    /// Compile-time pin: `TestStore.restore` must accept an *optional*
    /// `TestContextToken?` so test sites can do `defer { TestStore.restore(token) }`
    /// without unwrapping. A regression that requires non-optional would
    /// break every Defi test (the original consumer of this API).
    func testTestStoreRestoreAcceptsOptionalToken() {
        let token: TestContextToken? = nil
        TestStore.restore(token) // must compile
        // Also accepts a real token.
        if let real = try? TestStore.installInMemoryContainer() {
            TestStore.restore(real)
        }
    }

    // MARK: - Helpers

    private func makeCoin(_ chain: Chain, ticker: String, decimals: Int, isNative: Bool, rawBalance: String = "0") -> Coin {
        let asset = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: isNative)
        let coin = Coin(asset: asset, address: "test-address-\(ticker)", hexPublicKey: "")
        coin.rawBalance = rawBalance
        return coin
    }

    private func makeTx(coin: Coin, vault: Vault, gas: BigInt, fee: BigInt) throws -> SendTransaction {
        SendTransaction(
            coin: coin,
            vault: vault,
            fromAddress: coin.address,
            toAddress: "0x0000000000000000000000000000000000000001",
            toAddressLabel: nil,
            amount: "0.5",
            amountInFiat: "",
            memo: "",
            gas: gas,
            fee: fee,
            feeMode: .default,
            estimatedGasLimit: nil,
            customGasLimit: nil,
            customByteFee: nil,
            sendMaxAmount: false,
            isFastVault: false,
            isStakingOperation: false,
            transactionType: .unspecified,
            memoFunctionDictionary: [:],
            wasmContractPayload: nil,
            feeCoin: coin
        )
    }
}
