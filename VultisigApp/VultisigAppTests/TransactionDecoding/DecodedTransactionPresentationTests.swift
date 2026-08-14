//
//  DecodedTransactionPresentationTests.swift
//  VultisigAppTests
//
//  Where a decoded reading becomes the sentence someone approves a transaction
//  on. Two things are pinned above all: a fraction is announced as a fraction,
//  and a zero is never announced at all.
//

import BigInt
@testable import VultisigApp
import VultisigCommonData
import XCTest

@MainActor
final class DecodedTransactionPresentationTests: XCTestCase {

    /// ⚠️ The reported bug, end to end. A `tcy-:<bps>` withdrawal carries a
    /// literal zero amount, so the generic header read "You're sending 0 TCY".
    /// The memo commits to a SHARE, and the share is what gets said.
    func testAFractionalWithdrawalIsAnnouncedAsAShare() throws {
        let hero = try XCTUnwrap(DecodedTransactionPresentation.hero(
            for: DecodedTransaction(
                operation: .unstake,
                amount: .fraction(basisPoints: 5006, of: .transactionCoin),
                evidence: .memo
            ),
            coin: tcy
        ))

        guard case let .title(text, caption) = hero else {
            return XCTFail("expected a title hero, got \(hero)")
        }
        XCTAssertEqual(text, "youreUnstaking".localized)
        let share = try XCTUnwrap(caption)
        // Asserted without the decimal separator: the figure is formatted for
        // the running locale, so a machine set to a comma-decimal region renders
        // "50,06" and pinning "50.06" would fail on that machine alone.
        XCTAssertTrue(share.contains("50"), "expected the share, got \(share)")
        XCTAssertTrue(share.contains("06"), "expected the exact share, got \(share)")
        XCTAssertTrue(share.contains("TCY"), "expected the asset, got \(share)")
    }

    /// ⚠️ A liquidity withdrawal's fraction is a share of a two-sided POOL, not
    /// of a staked position, and the asset the caption would name is the
    /// transaction's coin rather than the pool — so `-:BTC.BTC:5000` read "50%
    /// of your staked RUNE", which is false twice over. The verb alone is what
    /// can honestly be said until that has copy of its own.
    func testALiquidityWithdrawalDoesNotClaimAStakedPosition() throws {
        let hero = try XCTUnwrap(DecodedTransactionPresentation.hero(
            for: DecodedTransaction(
                operation: .removeLiquidity,
                amount: .fraction(basisPoints: 5000, of: .transactionCoin),
                counterparty: .pool("BTC.BTC"),
                evidence: .memo
            ),
            coin: tcy
        ))

        guard case let .title(text, caption) = hero else {
            return XCTFail("expected a title hero, got \(hero)")
        }
        XCTAssertEqual(text, "youreRemovingLiquidity".localized)
        XCTAssertNil(caption, "a pool share must not be described as a staked position")
    }

    /// A full exit reads as 100%, not 99.99 or a rounding artefact.
    func testAFullExitReadsAsOneHundredPercent() throws {
        let hero = try XCTUnwrap(DecodedTransactionPresentation.hero(
            for: DecodedTransaction(
                operation: .unstake,
                amount: .fraction(basisPoints: 10_000, of: .transactionCoin),
                evidence: .memo
            ),
            coin: tcy
        ))
        guard case let .title(_, caption) = hero else { return XCTFail("expected a title hero") }
        XCTAssertTrue(try XCTUnwrap(caption).contains("100"))
    }

    /// The share reaches the caption, not just the title — the earlier version
    /// of this suite asserted the headline and left the figure unchecked, which
    /// is the half that can be wrong.
    func testTheCaptionCarriesTheShareAndTheAsset() throws {
        let hero = try XCTUnwrap(
            DecodedTransactionPresentation.hero(for: makePayload(memo: "tcy-:2500"))
        )
        guard case let .title(_, caption) = hero else {
            return XCTFail("expected a title hero, got \(hero)")
        }
        let share = try XCTUnwrap(caption)
        XCTAssertTrue(share.contains("25"), "expected the share, got \(share)")
        XCTAssertTrue(share.contains("TCY"), "expected the asset, got \(share)")
    }

    /// A real quantity is rendered against the transaction's own coin.
    func testAQuantityIsRenderedAtTheAssetsPrecision() throws {
        let hero = try XCTUnwrap(DecodedTransactionPresentation.hero(
            for: DecodedTransaction(
                operation: .bond,
                amount: .units(BigInt(150_000_000), of: .transactionCoin),
                evidence: .memo
            ),
            coin: tcy
        ))

        guard case let .send(title, coin) = hero else {
            return XCTFail("expected a send hero, got \(hero)")
        }
        XCTAssertEqual(title, "youreBonding".localized)
        XCTAssertEqual(coin.amount, "1.5")
        XCTAssertEqual(coin.ticker, "TCY")
    }

    /// ⚠️ The guard that stops the verb inheriting the bug. A zero quantity is
    /// shown as the verb alone — "You're unstaking 0 TCY" is the same defect in
    /// better clothes.
    func testAZeroQuantityIsNeverRendered() throws {
        let hero = try XCTUnwrap(DecodedTransactionPresentation.hero(
            for: DecodedTransaction(
                operation: .unstake,
                amount: .units(.zero, of: .transactionCoin),
                evidence: .memo
            ),
            coin: tcy
        ))
        guard case let .title(text, caption) = hero else {
            return XCTFail("expected a title hero, got \(hero)")
        }
        XCTAssertEqual(text, "youreUnstaking".localized)
        XCTAssertNil(caption)
    }

    /// ⚠️ Signed, exact, and still unrenderable: nothing knows how many decimals
    /// a receipt denom carries, so the verb is shown without a figure rather
    /// than with a scaled guess.
    func testASignedDenomAmountIsNotScaledIntoAFigure() throws {
        let hero = try XCTUnwrap(DecodedTransactionPresentation.hero(
            for: DecodedTransaction(
                operation: .unstake,
                amount: .units(BigInt(300_000_000), of: .denom("x/staking-tcy")),
                evidence: .wasmExecuteMsg
            ),
            coin: tcy
        ))
        guard case .title = hero else {
            return XCTFail("a receipt denom must not be rendered as a coin amount, got \(hero)")
        }
    }

    /// Operations the screens already describe correctly keep what they had.
    func testOperationsWithNothingToAddGetNoHero() {
        for operation: DecodedOperation in [.transfer, .swap, .approve, .unknown, .contractCall] {
            XCTAssertNil(
                DecodedTransactionPresentation.hero(
                    for: DecodedTransaction(operation: operation, amount: .unstated, evidence: .unread),
                    coin: tcy
                ),
                "\(operation) should keep the screen's existing header"
            )
        }
    }

    /// ⚠️ The caption interpolates TWO values, and Korean and Simplified Chinese
    /// put them in the opposite order to English — the asset first, then the
    /// share. With bare `%@` placeholders those two locales rendered the ticker
    /// where the percentage belongs, on the screen where someone approves a
    /// withdrawal. Positional specifiers are what make the order a property of
    /// the translation rather than of the call site.
    func testEveryLocaleUsesPositionalPlaceholdersForTheShareCaption() throws {
        var checked = 0

        for locale in ["en", "de", "es", "hr", "it", "ko", "pt", "zh-Hans"] {
            guard let path = Bundle.main.path(forResource: locale, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }

            let format = bundle.localizedString(
                forKey: "withdrawingShareOfStakedPosition", value: nil, table: nil
            )
            guard format != "withdrawingShareOfStakedPosition" else { continue }

            XCTAssertTrue(format.contains("%1$@"), "\(locale) must position the share explicitly")
            XCTAssertTrue(format.contains("%2$@"), "\(locale) must position the asset explicitly")
            XCTAssertFalse(
                format.contains("%@"),
                "\(locale) mixes bare and positional placeholders, which reorders unpredictably"
            )
            checked += 1
        }

        XCTAssertGreaterThan(checked, 1, "the locales were not readable, so this asserted nothing")
    }

    // MARK: - Composing with a simulation

    /// ⚠️ Decoding and simulation are INDEPENDENT readings and must not displace
    /// one another. A Blockaid simulation reports the balance changes a
    /// transaction produces; decoding reports which operation it is. Wiring the
    /// decoder into the resolver briefly put them in one slot, and since the
    /// resolver is asked before `?? viewModel.heroContent`, a decoded verb
    /// silently erased a simulation's figures and its fiat line.
    ///
    /// A co-signer reaches decoding through its own `heroContent`, where the
    /// verb is handed to the simulation as a title rather than replacing it.
    ///
    /// The verb a simulation would be given as its title, so its own figures
    /// survive.
    func testTheOperationTitleIsAvailableSeparatelyFromAWholeHero() {
        XCTAssertEqual(
            DecodedTransactionPresentation.operationTitle(for: makePayload(memo: "tcy-:5006")),
            "youreUnstaking".localized
        )
        XCTAssertNil(
            DecodedTransactionPresentation.operationTitle(for: makePayload(memo: "nothing parses this")),
            "an unreadable payload must not retitle a simulation"
        )
    }

    /// The whole path, for the case where nothing simulated the transaction:
    /// payload → decoder → presentation.
    func testAPayloadDecodesToAHeroWhenNothingElseDescribesIt() throws {
        let hero = try XCTUnwrap(
            DecodedTransactionPresentation.hero(for: makePayload(memo: "tcy-:5006"))
        )
        XCTAssertEqual(hero.title, "youreUnstaking".localized)
    }

    // MARK: - Fixtures

    private var tcy: Coin {
        Coin(
            asset: CoinMeta(
                chain: .thorChain, ticker: "TCY", logo: "tcy", decimals: 8,
                priceProviderId: "tcy", contractAddress: "", isNativeToken: false
            ),
            address: "thor1from",
            hexPublicKey: "02" + String(repeating: "00", count: 32)
        )
    }

    private func makePayload(memo: String) -> KeysignPayload {
        KeysignPayload(
            coin: tcy,
            toAddress: "thor1to",
            toAmount: .zero,
            chainSpecific: .THORChain(
                accountNumber: 1, sequence: 1, fee: 0, isDeposit: true, transactionType: 0
            ),
            utxos: [],
            memo: memo,
            swapPayload: nil,
            approvePayload: nil,
            vaultPubKeyECDSA: "pub",
            vaultLocalPartyID: "party",
            libType: LibType.DKLS.toString(),
            wasmExecuteContractPayload: nil,
            tronTransferContractPayload: nil,
            tronTriggerSmartContractPayload: nil,
            tronTransferAssetContractPayload: nil,
            qbtcClaimPayload: nil,
            isQbtcClaim: false,
            skipBroadcast: false,
            signData: nil
        )
    }
}
