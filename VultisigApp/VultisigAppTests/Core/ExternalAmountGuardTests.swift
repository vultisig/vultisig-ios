//
//  ExternalAmountGuardTests.swift
//  VultisigAppTests
//
//  The two paths that prefill the send form from outside the app: a
//  `vultisig://send` deeplink and a scanned `bitcoin:` / `ton://` URI.
//

import XCTest
@testable import VultisigApp

@MainActor
final class ExternalAmountGuardTests: XCTestCase {

    // MARK: - Why the guard rejects rather than normalises

    /// Verify renders `tx.amount`; the signed value comes from `amountDecimal`.
    func testScientificNotationDisplaysAndSignsDifferentValues() {
        let coin = SendFormFixture.makeBTC()
        let displayed = "1e5"

        let signed = SendCryptoLogic.amountDecimal(coin: coin, amount: displayed)

        XCTAssertEqual(signed, Decimal(100_000))
        XCTAssertNotEqual(displayed, "\(signed)")
        XCTAssertFalse(displayed.isValidDecimal(), "the form must refuse it before Verify can show it")
    }

    // MARK: - Deeplink boundary

    private func sendAmount(from query: String, locale: Locale = Locale(identifier: "en_US")) throws -> String? {
        let url = URL(string: "vultisig://send?assetChain=ethereum&assetTicker=ETH&toAddress=0xdead&\(query)")!
        return try DeeplinkLogic(locale: locale).extractParameters(url, vaults: []).sendAmount
    }

    func testDeeplinkDropsScientificNotationAmount() throws {
        XCTAssertNil(try sendAmount(from: "amount=1e5"))
        XCTAssertNil(try sendAmount(from: "amount=1E5"))
        XCTAssertNil(try sendAmount(from: "amount=2.5e3"))
        XCTAssertNil(try sendAmount(from: "amount=1e-3"))
        XCTAssertNil(try sendAmount(from: "amount=0x1F"))
    }

    func testDeeplinkKeepsPlainDecimalAmount() throws {
        XCTAssertEqual(try sendAmount(from: "amount=1.5"), "1.5")
        XCTAssertEqual(try sendAmount(from: "amount=0.00000001"), "0.00000001")
        XCTAssertEqual(try sendAmount(from: "amount=100000"), "100000")
    }

    func testDeeplinkWithoutAmountStaysNil() throws {
        XCTAssertNil(try sendAmount(from: "memo=hello"))
    }

    func testDeeplinkWithRejectedAmountStillCarriesAddress() throws {
        let url = URL(string: "vultisig://send?assetChain=ethereum&assetTicker=ETH&toAddress=0xdead&amount=1e5")!

        let result = try DeeplinkLogic(locale: Locale(identifier: "en_US")).extractParameters(url, vaults: [])

        XCTAssertEqual(result.address, "0xdead")
        XCTAssertEqual(result.type, .Send)
        XCTAssertNil(result.sendAmount)
    }

    // MARK: - Scanned crypto-URI boundary

    func testScannedURIDropsScientificNotationAmount() {
        XCTAssertNil(AddressResult.fromURI("bitcoin:bc1qexampleaddress?amount=1e5").amount)
        XCTAssertNil(AddressResult.fromURI("bitcoin:bc1qexampleaddress?amount=2.5e3").amount)
        XCTAssertNil(AddressResult.fromURI("ton://transfer/EQabc?amount=1e5").amount)
    }

    func testScannedURIKeepsPlainDecimalAmount() {
        XCTAssertEqual(AddressResult.fromURI("bitcoin:bc1qexampleaddress?amount=0.5").amount, "0.5")
        XCTAssertEqual(AddressResult.fromURI("ton://transfer/EQabc?amount=12.25").amount, "12.25")
    }

    func testScannedURIWithRejectedAmountKeepsAddressAndMessage() {
        let result = AddressResult.fromURI("bitcoin:bc1qexampleaddress?amount=1e5&message=coffee")

        XCTAssertEqual(result.address, "bc1qexampleaddress")
        XCTAssertEqual(result.memo, "coffee")
        XCTAssertNil(result.amount)
    }

    // MARK: - Comma-decimal locales

    /// A locale-aware parse reads the `.` in a machine-supplied `0.005` as a
    /// grouping separator and returns 5, in five of the eight shipping locales.
    func testExternalAmountSurvivesCommaDecimalLocales() {
        for identifier in ["en_US", "de_DE", "zh_Hans_CN", "es_ES", "ko_KR", "it_IT", "pt_BR", "hr_HR"] {
            let locale = Locale(identifier: identifier)

            guard let staged = "0.005".externalAmount(locale: locale) else {
                return XCTFail("\(identifier) rejected a canonical dot-decimal amount")
            }

            XCTAssertEqual(
                staged.parseInput(locale: locale), Decimal(string: "0.005"),
                "\(identifier) staged \(staged), which its own parser must read back as 0.005"
            )
        }
    }

    func testExternalAmountDoesNotPromoteFractionToThousands() {
        for identifier in ["pt_BR", "de_DE"] {
            let locale = Locale(identifier: identifier)
            let staged = "1.234".externalAmount(locale: locale)

            XCTAssertEqual(staged?.parseInput(locale: locale), Decimal(string: "1.234"), identifier)
        }
    }

    func testExternalAmountRejectsEverythingNotPlainDotDecimal() {
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "pt_BR")] {
            for candidate in ["1e5", "1E5", "2.5e3", "1e-3", "0x1F", "1,5", "1.2.3", "-5", "1 234", "abc", "", ".", "  0.5  "] {
                XCTAssertNil(
                    candidate.externalAmount(locale: locale),
                    "\(locale.identifier) must reject \(candidate.isEmpty ? "(empty)" : candidate)"
                )
            }
        }
    }

    /// BIP-321 admits a bare separator on either side, so rejecting `1.` / `.5`
    /// would drop a spec-legal QR amount. `""` and `"."` carry no digit.
    func testExternalAmountAcceptsTheGrammarsBareSeparatorForms() {
        for identifier in ["en_US", "pt_BR", "de_DE"] {
            let locale = Locale(identifier: identifier)

            XCTAssertEqual("1.".externalAmount(locale: locale)?.parseInput(locale: locale), Decimal(1), identifier)
            XCTAssertEqual(
                ".5".externalAmount(locale: locale)?.parseInput(locale: locale),
                Decimal(string: "0.5"), identifier
            )
        }
    }

    /// Previously slipped through on dot-decimal locales, where the early return
    /// skipped the final check.
    func testExternalAmountRejectsOversizedAmountOnEveryLocale() {
        let oversized = String(repeating: "9", count: 309)

        for identifier in ["en_US", "pt_BR", "de_DE", "ko_KR"] {
            XCTAssertNil(
                oversized.externalAmount(locale: Locale(identifier: identifier)),
                "\(identifier) staged an amount its own parser cannot read"
            )
        }
    }

    func testDeeplinkStagesCommaLocaleAmountThatReadsBackCorrectly() throws {
        for identifier in ["pt_BR", "de_DE"] {
            let locale = Locale(identifier: identifier)
            let staged = try sendAmount(from: "amount=0.005", locale: locale)

            XCTAssertEqual(staged?.parseInput(locale: locale), Decimal(string: "0.005"), identifier)
            XCTAssertNil(try sendAmount(from: "amount=1e5", locale: locale), identifier)
        }
    }

    func testScannedURIStagesCommaLocaleAmountThatReadsBackCorrectly() {
        let locale = Locale(identifier: "pt_BR")
        let staged = AddressResult.fromURI("bitcoin:bc1qexampleaddress?amount=0.005", locale: locale).amount

        XCTAssertEqual(staged?.parseInput(locale: locale), Decimal(string: "0.005"))
    }

    // MARK: - The live function-call / DeFi amount gate

    /// The live gate on ~19 function-call and DeFi amount fields.
    func testAmountBalanceValidatorRejectsScientificNotation() {
        let validator = AmountBalanceValidator(balance: Decimal(1_000_000))

        for candidate in ["1e5", "1E5", "2.5e3", "0x1F"] {
            XCTAssertThrowsError(try validator.validate(value: candidate), candidate)
        }
    }

    func testAmountBalanceValidatorStillAcceptsPlainAmounts() {
        let validator = AmountBalanceValidator(balance: Decimal(1_000_000))

        XCTAssertNoThrow(try validator.validate(value: "0.5"))
        XCTAssertNoThrow(try validator.validate(value: "1000"))
    }
}
