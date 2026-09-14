import XCTest
@testable import VultisigApp

final class SwapAmountInputTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    func testRateMustBePositiveFiniteAndRepresentable() {
        for rate: Double? in [nil, 0, -1, .nan, .infinity, 1e-200, 1e200] {
            XCTAssertNil(SwapAmountInput.Context(sourceID: "a", currency: "USD", decimals: 18, rate: rate))
        }
    }

    func testSubCentRateKeepsDecimalExponentPrecision() {
        XCTAssertEqual(context(rate: 0.00001234)?.rate, Decimal(string: "0.00001234"))
    }

    func testFiatConversionTruncatesDownToBaseUnits() {
        var input = makeInput(rate: 2.5)
        XCTAssertEqual(input.editFiat("10", locale: locale), "4")
        XCTAssertEqual(input.editFiat("2,5", locale: Locale(identifier: "de_DE")), "1")
        input = makeInput(rate: 3, decimals: 6)
        XCTAssertEqual(input.editFiat("1", locale: locale), "0.333333")
        XCTAssertEqual(input.editFiat("2", locale: locale), "0.666666")
        XCTAssertEqual(input.editFiat("0.000001", locale: locale), "0")
    }

    func testStrictLocalizedParsingWithoutDoublePrecisionLoss() {
        XCTAssertEqual(SwapAmountInput.parse("1.234,56", locale: Locale(identifier: "de_DE")), Decimal(string: "1234.56"))
        XCTAssertEqual(SwapAmountInput.parse("١٢٫٥", locale: Locale(identifier: "ar_EG")), Decimal(string: "12.5"))
        XCTAssertEqual(SwapAmountInput.parse("123456789012345678.123456789012345678", locale: locale),
                       Decimal(string: "123456789012345678.123456789012345678"))
        for invalid in ["12abc", "-1", "1e5", "$12", "12,34", "0,500", "1.2.3", String(repeating: "9", count: 39)] {
            XCTAssertNil(SwapAmountInput.parse(invalid, locale: locale), invalid)
        }
        XCTAssertEqual(SwapAmountInput.parse("1.", locale: locale), 1)
        XCTAssertEqual(SwapAmountInput.parse("", locale: locale), 0)
    }

    func testFocusedRateRefreshUsesCapturedPriceThenReseedsWithoutConversion() {
        var input = makeInput(rate: 2)
        input.setEditing(true, tokenAmount: 4, locale: locale)
        input.refresh(context: context(rate: 5), tokenAmount: 4, locale: locale)
        XCTAssertEqual(input.editFiat("10", locale: locale), "5")
        XCTAssertEqual(input.context?.rate, 2)
        input.setEditing(false, tokenAmount: 5, locale: locale)
        XCTAssertEqual(input.context?.rate, 5)
        XCTAssertEqual(input.draft, "25")
    }

    func testPresetsAndTogglesOnlyRenderCanonicalTokens() {
        var input = makeInput(rate: 3)
        let exact = Decimal(string: "0.123456789012345678")!
        for _ in 0..<10 {
            input.synchronize(tokenAmount: exact, locale: locale)
            input.toggle(tokenAmount: exact, locale: locale)
        }
        XCTAssertTrue(input.isFiat)
        XCTAssertEqual(input.draft, "0.37")
    }

    func testMissingRateAndIdentityChangesExitFiatMode() {
        for next in [nil, context(rate: 3, source: "b"), context(rate: 3, currency: "EUR")] {
            var input = makeInput(rate: 2)
            input.setEditing(true, tokenAmount: 4)
            input.refresh(context: next, tokenAmount: 4)
            XCTAssertFalse(input.isFiat)
        }
    }

    func testInvalidDraftCannotKeepPreviousTokenValue() {
        var input = makeInput(rate: 2)
        XCTAssertEqual(input.editFiat("10", locale: locale), "5")
        XCTAssertEqual(input.editFiat("10..", locale: locale), "")
        XCTAssertEqual(input.draft, "10..")
    }

    func testUnrepresentableFiatDisplayExitsModeWithoutBlankActionableField() {
        var input = makeInput(rate: 1e100)
        XCTAssertTrue(input.isFiat)
        input.synchronize(tokenAmount: Decimal(string: "1e100")!, locale: locale)
        XCTAssertFalse(input.isFiat)
        XCTAssertNil(input.context)
    }

    func testRoundedFiatDisplayNeverRevaluesQuantizedTokens() {
        var input = makeInput(rate: 3)
        let token = input.editFiat("10", locale: locale)
        XCTAssertEqual(token, "3.333333333333333333")
        input.setEditing(false, tokenAmount: SwapAmountInput.parse(token, locale: locale)!, locale: locale)
        XCTAssertEqual(input.draft, "10")
        input.synchronize(tokenAmount: Decimal(string: "0.000000000001")!, locale: locale)
        XCTAssertEqual(input.draft, "0.000000000003")
    }

    func testDisplayPrecisionLossDoesNotDisableFiat() {
        var input = makeInput(rate: 0.1 + 0.2)
        input.synchronize(tokenAmount: Decimal(string: "54321.123456789012345678")!, locale: locale)
        XCTAssertTrue(input.isFiat)
        XCTAssertNotNil(input.context)
    }

    func testRateRecoveryRetainsActualFocusState() {
        var input = makeInput(rate: 2)
        input.setEditing(true, tokenAmount: 5, locale: locale)
        input.refresh(context: nil, tokenAmount: 5, locale: locale)
        input.refresh(context: context(rate: 2), tokenAmount: 5, locale: locale)
        input.toggle(tokenAmount: 5, locale: locale)
        _ = input.editFiat("10.", locale: locale)
        input.refresh(context: context(rate: 5), tokenAmount: 5, locale: locale)
        XCTAssertEqual(input.draft, "10.")
        XCTAssertEqual(input.context?.rate, 2)
    }

    private func context(rate: Double, source: String = "a", currency: String = "USD", decimals: Int = 18) -> SwapAmountInput.Context? {
        SwapAmountInput.Context(sourceID: source, currency: currency, decimals: decimals, rate: rate)
    }

    private func makeInput(rate: Double, decimals: Int = 18) -> SwapAmountInput {
        var input = SwapAmountInput()
        input.refresh(context: context(rate: rate, decimals: decimals), tokenAmount: 0, locale: locale)
        input.toggle(tokenAmount: 0, locale: locale)
        return input
    }
}
