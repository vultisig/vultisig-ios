//
//  CustomMemoTransactionViewModelTests.swift
//  VultisigAppTests
//
//  Carries the assertions from the deleted `FunctionCallCustomTests` — which
//  assets the form offers per chain, the pre-selection, the token/memo/amount
//  validity gate — plus the two things that changed on the way: the asset list
//  is the vault's own coins rather than a ticker allowlist with a phantom
//  fallback, and it covers the whole TCY family rather than the one exact
//  ticker.
//

@testable import VultisigApp
import Foundation
import XCTest

@MainActor
final class CustomMemoTransactionViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func thorCoin(_ ticker: String, rawBalance: String = "100000000000") -> Coin {
        FunctionCallFixture.makeCoin(
            .thorChain,
            ticker: ticker,
            decimals: 8,
            isNative: ticker == "RUNE",
            rawBalance: rawBalance,
            address: FunctionCallFixture.thorAddress
        )
    }

    private func mayaCoin(_ ticker: String) -> Coin {
        FunctionCallFixture.makeCoin(
            .mayaChain,
            ticker: ticker,
            decimals: 10,
            isNative: ticker == "CACAO",
            address: FunctionCallFixture.mayaAddress
        )
    }

    private func loadedViewModel(
        coin: Coin,
        vault: Vault,
        locale: Locale = Locale(identifier: "en_US")
    ) -> CustomMemoTransactionViewModel {
        let viewModel = CustomMemoTransactionViewModel(coin: coin, vault: vault, locale: locale)
        viewModel.onLoad()
        return viewModel
    }

    private func tickers(_ viewModel: CustomMemoTransactionViewModel) -> [String] {
        viewModel.depositableCoins.map { $0.ticker }
    }

    // MARK: - Which assets the form offers

    /// Legacy loaded RUNE / RUJI / TCY from the vault on THORChain.
    func testThorchainOffersTheVaultsDepositableCoins() {
        let rune = thorCoin("RUNE")
        let ruji = thorCoin("RUJI")
        let tcy = thorCoin("TCY")
        let vault = FunctionCallFixture.makeVault(coins: [rune, ruji, tcy])

        XCTAssertEqual(tickers(loadedViewModel(coin: rune, vault: vault)), ["RUNE", "RUJI", "TCY"])
    }

    /// The mismatch this migration closes: the legacy dropdown sent any
    /// THORChain ticker *containing* "TCY" to this form, while the form's own
    /// token loading matched "TCY" exactly — so a wrapper holder arrived at a
    /// picker that could not offer the coin they arrived for.
    func testThorchainOffersTheWholeTcyFamily() {
        let rune = thorCoin("RUNE")
        let tcy = thorCoin("TCY")
        let sTCY = thorCoin("sTCY")
        let yTCY = thorCoin("yTCY")
        let vault = FunctionCallFixture.makeVault(coins: [rune, tcy, sTCY, yTCY])

        XCTAssertEqual(tickers(loadedViewModel(coin: rune, vault: vault)), ["RUNE", "TCY", "sTCY", "yTCY"])
    }

    /// A wrapper holder now opens the form on their own coin instead of on the
    /// "Select Token" placeholder.
    func testAWrappedTcyPreSelectsItself() {
        let sTCY = thorCoin("sTCY")
        let vault = FunctionCallFixture.makeVault(coins: [thorCoin("RUNE"), sTCY])

        let viewModel = loadedViewModel(coin: sTCY, vault: vault)
        XCTAssertEqual(viewModel.selectedCoin?.ticker, "sTCY")
    }

    /// Legacy loaded CACAO / MAYA / AZTEC from the vault on MayaChain.
    func testMayachainOffersTheVaultsDepositableCoins() {
        let cacao = mayaCoin("CACAO")
        let maya = mayaCoin("MAYA")
        let aztec = mayaCoin("AZTEC")
        let vault = FunctionCallFixture.makeVault(coins: [cacao, maya, aztec])

        XCTAssertEqual(tickers(loadedViewModel(coin: cacao, vault: vault)), ["CACAO", "MAYA", "AZTEC"])
    }

    /// The test networks run the same `MsgDeposit`; leaving them out left the
    /// picker empty and the form permanently unsubmittable, on the one chain
    /// family whose only operation this is.
    func testTheThorchainTestNetworksOfferTheirOwnCoins() {
        for chain in [Chain.thorChainChainnet, Chain.thorChainStagenet] {
            let rune = FunctionCallFixture.makeCoin(chain, ticker: "RUNE", decimals: 8, isNative: true)
            let vault = FunctionCallFixture.makeVault(coins: [rune])

            let viewModel = loadedViewModel(coin: rune, vault: vault)
            XCTAssertEqual(tickers(viewModel), ["RUNE"], "\(chain.rawValue) offered no asset to pick")
            XCTAssertEqual(viewModel.selectedCoin?.chain, chain)
        }
    }

    /// The picked asset becomes the coin the memo is deposited against, so it
    /// has to resolve on this form's chain and on no other. A mainnet and a
    /// stagenet RUNE are different coins.
    func testTheAssetListIsScopedToTheFormsOwnChain() {
        let mainnetRune = thorCoin("RUNE")
        let stagenetRune = FunctionCallFixture.makeCoin(
            .thorChainStagenet,
            ticker: "RUNE",
            decimals: 8,
            isNative: true
        )
        let vault = FunctionCallFixture.makeVault(coins: [mainnetRune, stagenetRune])

        XCTAssertEqual(loadedViewModel(coin: stagenetRune, vault: vault).selectedCoin?.chain, .thorChainStagenet)
        XCTAssertEqual(loadedViewModel(coin: mainnetRune, vault: vault).selectedCoin?.chain, .thorChain)
    }

    /// A coin the form cannot deposit with leaves the picker empty rather than
    /// silently falling back to the chain's native asset — legacy's "Select
    /// Token" placeholder, which its validity gate refused to submit through.
    func testAnUnsupportedEntryCoinSelectsNothing() {
        let rune = thorCoin("RUNE")
        let secured = thorCoin("BTC-BTC")
        let vault = FunctionCallFixture.makeVault(coins: [rune, secured])

        let viewModel = loadedViewModel(coin: secured, vault: vault)
        XCTAssertNil(viewModel.selectedCoin)
        XCTAssertEqual(tickers(viewModel), ["RUNE"])
    }

    /// Legacy appended a fallback *ticker* the vault did not hold. Picking it
    /// satisfied its "token selected" gate but resolved to no coin, so the
    /// deposit was built against whatever coin the screen happened to hold
    /// while the dropdown named another. An empty list now means no builder.
    func testAVaultWithNoDepositableCoinBuildsNothing() {
        let secured = thorCoin("BTC-BTC")
        let vault = FunctionCallFixture.makeVault(coins: [secured])

        let viewModel = loadedViewModel(coin: secured, vault: vault)
        XCTAssertTrue(viewModel.depositableCoins.isEmpty)
        viewModel.memoField.value = "SWAP:BTC.BTC:bc1qexample"
        XCTAssertNil(viewModel.transactionBuilder)
    }

    // MARK: - The memo

    /// The property the whole form exists for, asserted through the
    /// view-model rather than through the builder alone.
    func testTheMemoReachesTheBuilderVerbatim() {
        let rune = thorCoin("RUNE")
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let awkward = [
            "arbitrary-memo-string",
            "SWAP:BTC.BTC:bc1qexample:12345/3/0",
            " leading and trailing ",
            "MiXeD CaSe",
            "colons:everywhere:::",
            "unicode ünïcodé 中文 🚀",
            "tab\tseparated"
        ]

        for memo in awkward {
            let viewModel = loadedViewModel(coin: rune, vault: vault)
            viewModel.memoField.value = memo
            XCTAssertEqual(viewModel.transactionBuilder?.memo, memo, "The form rewrote the memo")
        }
    }

    func testAnEmptyMemoCannotReachTheBuilder() {
        let rune = thorCoin("RUNE")
        let vault = FunctionCallFixture.makeVault(coins: [rune])

        let viewModel = loadedViewModel(coin: rune, vault: vault)
        XCTAssertNil(viewModel.transactionBuilder, "A pristine form must not build")

        viewModel.memoField.value = "memo"
        XCTAssertNotNil(viewModel.transactionBuilder)

        viewModel.memoField.value = ""
        XCTAssertNil(viewModel.transactionBuilder, "Clearing the memo must close the gate again")
    }

    /// Deliberately stricter than legacy, which gated on `!custom.isEmpty` and
    /// so accepted a memo of pure spaces. That names no operation on either
    /// chain and buys a wasted deposit fee. The memo that *is* submitted is
    /// still never trimmed — see `testTheMemoReachesTheBuilderVerbatim`.
    func testAWhitespaceOnlyMemoCannotReachTheBuilder() {
        let rune = thorCoin("RUNE")
        let vault = FunctionCallFixture.makeVault(coins: [rune])

        for blank in ["   ", "\t", "\n", " \t\n "] {
            let viewModel = loadedViewModel(coin: rune, vault: vault)
            viewModel.memoField.value = blank
            XCTAssertNil(viewModel.transactionBuilder, "A blank memo must not build")
        }
    }

    /// A memo alone is not enough: legacy required a token too.
    func testAMemoWithNoSelectedAssetCannotReachTheBuilder() {
        let rune = thorCoin("RUNE")
        let secured = thorCoin("BTC-BTC")
        let vault = FunctionCallFixture.makeVault(coins: [rune, secured])

        let viewModel = loadedViewModel(coin: secured, vault: vault)
        viewModel.memoField.value = "memo"
        XCTAssertNil(viewModel.transactionBuilder)

        viewModel.selectedAsset = THORChainAsset(thorchainAsset: "THOR.RUNE", asset: rune.toCoinMeta())
        XCTAssertEqual(viewModel.transactionBuilder?.coin.ticker, "RUNE")
    }

    // MARK: - The amount

    /// The amount is optional — a memo-only `MsgDeposit` attaches nothing.
    func testAnEmptyAmountAttachesZero() {
        let rune = thorCoin("RUNE")
        let vault = FunctionCallFixture.makeVault(coins: [rune])

        let viewModel = loadedViewModel(coin: rune, vault: vault)
        viewModel.memoField.value = "memo"
        XCTAssertEqual(viewModel.transactionBuilder?.amount, "0")
    }

    func testAnAmountWithinBalanceIsAttached() {
        let rune = thorCoin("RUNE", rawBalance: "100000000")   // 1 RUNE
        let vault = FunctionCallFixture.makeVault(coins: [rune])

        let viewModel = loadedViewModel(coin: rune, vault: vault)
        viewModel.memoField.value = "memo"
        viewModel.amountField.value = "0.5"

        XCTAssertEqual(viewModel.transactionBuilder?.amount.toDecimal(), Decimal(string: "0.5"))
    }

    /// Legacy pin: an amount above the coin balance must fail the submit-time
    /// gate. Its no-arg predicate let one navigate past Continue.
    func testAnAmountOverBalanceCannotReachTheBuilder() {
        let rune = thorCoin("RUNE", rawBalance: "100000000")   // 1 RUNE
        let vault = FunctionCallFixture.makeVault(coins: [rune])

        let viewModel = loadedViewModel(coin: rune, vault: vault)
        viewModel.memoField.value = "memo"
        viewModel.amountField.value = "2"

        XCTAssertNil(viewModel.transactionBuilder)
    }

    func testAnUnparseableAmountCannotReachTheBuilder() {
        let rune = thorCoin("RUNE")
        let vault = FunctionCallFixture.makeVault(coins: [rune])

        for garbage in ["abc", "1.2.3", "-1", "1e5"] {
            let viewModel = loadedViewModel(coin: rune, vault: vault)
            viewModel.memoField.value = "memo"
            viewModel.amountField.value = garbage
            XCTAssertNil(viewModel.transactionBuilder, "\(garbage) was accepted as an amount")
        }
    }

    /// Switching asset moves the balance ceiling without any field value
    /// changing, so the published `validForm` is a run-loop turn behind and
    /// cannot be what the submission is judged on.
    func testSwitchingToASmallerBalanceInvalidatesAnAlreadyTypedAmount() {
        let rune = thorCoin("RUNE", rawBalance: "100000000")   // 1 RUNE
        let tcy = thorCoin("TCY", rawBalance: "10000000")      // 0.1 TCY
        let vault = FunctionCallFixture.makeVault(coins: [rune, tcy])

        let viewModel = loadedViewModel(coin: rune, vault: vault)
        viewModel.memoField.value = "memo"
        viewModel.amountField.value = "0.5"
        XCTAssertNotNil(viewModel.transactionBuilder)

        viewModel.selectedAsset = THORChainAsset(thorchainAsset: "THOR.TCY", asset: tcy.toCoinMeta())
        XCTAssertNil(viewModel.transactionBuilder, "0.5 exceeds the TCY balance and must not build")
    }

    // MARK: - Locale

    /// The amount is read in the form's locale and refuses the other
    /// convention outright, rather than reinterpreting it: `1,5` is one and a
    /// half on a comma-decimal machine, and `1.5` there is not a number at all.
    ///
    /// Asserted on the builder's `Decimal` rather than on its rendered `amount`
    /// string. The string is produced by `Decimal.formatToDecimal(digits:)`,
    /// which reads `Locale.current` — on a dot-decimal test host, reading it
    /// back would exercise the host's convention, not the injected one, and the
    /// assertion would say nothing about German at all.
    func testTheAmountIsReadInTheFormsLocale() {
        let rune = thorCoin("RUNE")
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let german = Locale(identifier: "de_DE")

        let commaDecimal = loadedViewModel(coin: rune, vault: vault, locale: german)
        commaDecimal.memoField.value = "memo"
        commaDecimal.amountField.value = "1,5"
        let builder = commaDecimal.transactionBuilder as? CustomMemoTransactionBuilder
        XCTAssertEqual(builder?.customAmount, Decimal(string: "1.5"))

        let dotDecimal = loadedViewModel(coin: rune, vault: vault, locale: german)
        dotDecimal.memoField.value = "memo"
        dotDecimal.amountField.value = "1.5"
        XCTAssertNil(dotDecimal.transactionBuilder, "1.5 is not a number in a comma-decimal locale")
    }

    /// Grouped input in the form's own convention — what the percentage buttons
    /// write into the field — is read, not refused.
    func testAGroupedAmountInTheFormsLocaleIsAccepted() {
        let rune = thorCoin("RUNE", rawBalance: "10000000000000")   // 100000 RUNE
        let vault = FunctionCallFixture.makeVault(coins: [rune])
        let german = Locale(identifier: "de_DE")

        let viewModel = loadedViewModel(coin: rune, vault: vault, locale: german)
        viewModel.memoField.value = "memo"
        viewModel.amountField.value = "12.345,5"

        let builder = viewModel.transactionBuilder as? CustomMemoTransactionBuilder
        XCTAssertEqual(builder?.customAmount, Decimal(string: "12345.5"))
    }
}
