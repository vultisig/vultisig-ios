//
//  OperationVocabularyTests.swift
//  VultisigAppTests
//
//  Requires an explicit presentation decision for every decoded operation.
//

@testable import VultisigApp
import XCTest

final class OperationVocabularyTests: XCTestCase {

    /// Every operation is either named or deliberately silent.
    func testEveryOperationIsNamedOrDeliberatelySilent() {
        for operation in DecodedOperation.allCases {
            let named = DecodedTransactionPresentation.title(for: operation) != nil
            let silent = DecodedTransactionPresentation.deliberatelySilent[operation] != nil

            XCTAssertTrue(
                named || silent,
                """
                \(operation) has no verb and no reason for not having one. Either \
                give it a title in `title(for:)` — with the key present in all \
                eight shipping locales — or add it to `deliberatelySilent` saying \
                what would have to change.
                """
            )
        }
    }

    /// No operation can be both named and silent.
    func testNoOperationIsBothNamedAndSilent() {
        for operation in DecodedOperation.allCases {
            let named = DecodedTransactionPresentation.title(for: operation) != nil
            let silent = DecodedTransactionPresentation.deliberatelySilent[operation] != nil
            XCTAssertFalse(named && silent, "\(operation) is named AND listed as silent")
        }
    }

    /// Every silent operation records why.
    func testEverySilentOperationStatesWhy() {
        for (operation, reason) in DecodedTransactionPresentation.deliberatelySilent {
            XCTAssertFalse(
                reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(operation) is listed as silent with an empty reason"
            )
        }
    }

    /// Pins operation-to-verb semantics, not merely key existence.
    func testEachNamedOperationUsesItsOwnVerb() {
        let expected: [DecodedOperation: String] = [
            .stake: "youreStaking",
            .unstake: "youreUnstaking",
            .claimRewards: "youreClaiming",
            .bond: "youreBonding",
            .unbond: "youreUnbonding",
            .rebond: "youreRebonding",
            .leave: "youreLeaving",
            .securedAssetDeposit: "youreDepositing",
            .securedAssetWithdraw: "youreWithdrawing",
            .switchChain: "youreSwitching",
            .limitOrderPlacement: "yourePlacingOrder",
            .limitOrderCancel: "youreCancellingOrder",
            .delegate: "youreDelegating",
            .undelegate: "youreUndelegating",
            .redelegate: "youreRedelegating",
            .addLiquidity: "youreAddingLiquidity",
            .redeem: "youreRedeeming",
            .mint: "youreMinting",
            .merge: "youreMerging",
            .unmerge: "youreUnmerging",
            .ibcTransfer: "youreBridging"
        ]

        for (operation, key) in expected {
            XCTAssertEqual(
                DecodedTransactionPresentation.localizationKey(for: operation), key,
                "\(operation) is wired to the wrong verb"
            )
        }

        let named = DecodedOperation.allCases.filter {
            DecodedTransactionPresentation.localizationKey(for: $0) != nil
        }
        XCTAssertEqual(
            Set(named), Set(expected.keys),
            "an operation gained or lost a verb without this mapping being updated"
        )
    }

    /// Every named operation resolves in every shipping locale.
    func testEveryNamedOperationResolvesInEveryShippingLocale() throws {
        let locales = ["en", "de", "es", "hr", "it", "ko", "pt", "zh-Hans"]

        // Keep this list synchronized with the bundle's shipping locales.
        let shipped = Set(Bundle.main.localizations).subtracting(["Base"])
        XCTAssertEqual(
            Set(locales), shipped,
            "the app's shipping locales changed — every named verb needs copy in the new set"
        )

        for operation in DecodedOperation.allCases {
            guard let key = DecodedTransactionPresentation.localizationKey(for: operation) else { continue }

            for locale in locales {
                let bundle = try XCTUnwrap(
                    Bundle(for: Self.self).path(forResource: locale, ofType: "lproj").flatMap(Bundle.init(path:))
                        ?? Bundle.main.path(forResource: locale, ofType: "lproj").flatMap(Bundle.init(path:)),
                    "no \(locale).lproj in the bundle"
                )

                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertNotEqual(
                    value, key,
                    "\(operation) has no verb in \(locale) — `\(key)` is missing, so that locale shows the raw key"
                )
            }
        }
    }
}
