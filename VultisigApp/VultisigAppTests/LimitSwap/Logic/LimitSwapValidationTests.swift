//
//  LimitSwapValidationTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

final class LimitSwapValidationTests: XCTestCase {

    // MARK: - Valid input passes

    func testValidInputsReturnNoErrors() {
        XCTAssertEqual(validateLimitSwapInputs(.valid()), [])
    }

    // MARK: - source_amount

    func testZeroSourceAmountIsRejected() {
        let errors = validateLimitSwapInputs(.valid(sourceAmount: 0))
        XCTAssertTrue(errors.contains(.sourceAmountNotPositive))
    }

    func testNegativeSourceAmountIsRejected() {
        let errors = validateLimitSwapInputs(.valid(sourceAmount: -1))
        XCTAssertTrue(errors.contains(.sourceAmountNotPositive))
    }

    // MARK: - target_price

    func testZeroTargetPriceIsRejected() {
        let errors = validateLimitSwapInputs(.valid(targetPrice: 0))
        XCTAssertTrue(errors.contains(.targetPriceNotPositive))
    }

    func testNegativeTargetPriceIsRejected() {
        let errors = validateLimitSwapInputs(.valid(targetPrice: Decimal(string: "-0.5")!))
        XCTAssertTrue(errors.contains(.targetPriceNotPositive))
    }

    // MARK: - expiry_hours

    func testExpiryHours12IsAccepted() {
        let errors = validateLimitSwapInputs(.valid(expiryHours: 12))
        XCTAssertFalse(errors.contains(where: { if case .expiryHoursUnsupported = $0 { return true } else { return false } }))
    }

    func testExpiryHours24IsAccepted() {
        let errors = validateLimitSwapInputs(.valid(expiryHours: 24))
        XCTAssertFalse(errors.contains(where: { if case .expiryHoursUnsupported = $0 { return true } else { return false } }))
    }

    func testExpiryHours72IsAccepted() {
        let errors = validateLimitSwapInputs(.valid(expiryHours: 72))
        XCTAssertFalse(errors.contains(where: { if case .expiryHoursUnsupported = $0 { return true } else { return false } }))
    }

    func testExpiryHours6IsRejected() {
        let errors = validateLimitSwapInputs(.valid(expiryHours: 6))
        XCTAssertTrue(errors.contains(.expiryHoursUnsupported(6)))
    }

    func testExpiryHours100IsRejected() {
        let errors = validateLimitSwapInputs(.valid(expiryHours: 100))
        XCTAssertTrue(errors.contains(.expiryHoursUnsupported(100)))
    }

    // MARK: - dest_address

    func testEmptyDestAddressIsRejected() {
        let errors = validateLimitSwapInputs(.valid(destAddress: ""))
        XCTAssertTrue(errors.contains(.destAddressEmpty))
    }

    func testWhitespaceOnlyDestAddressIsRejected() {
        let errors = validateLimitSwapInputs(.valid(destAddress: "   "))
        XCTAssertTrue(errors.contains(.destAddressEmpty))
    }

    // MARK: - asset format (<chain>.<symbol>)

    func testSourceAssetMissingDotIsRejected() {
        let errors = validateLimitSwapInputs(.valid(sourceAsset: "BTC"))
        XCTAssertTrue(errors.contains(.sourceAssetMalformed("BTC")))
    }

    func testTargetAssetMissingDotIsRejected() {
        let errors = validateLimitSwapInputs(.valid(targetAsset: "ETH"))
        XCTAssertTrue(errors.contains(.targetAssetMalformed("ETH")))
    }

    func testSourceAssetWithEmptyChainIsRejected() {
        let errors = validateLimitSwapInputs(.valid(sourceAsset: ".BTC"))
        XCTAssertTrue(errors.contains(.sourceAssetMalformed(".BTC")))
    }

    func testTargetAssetWithEmptySymbolIsRejected() {
        let errors = validateLimitSwapInputs(.valid(targetAsset: "ETH."))
        XCTAssertTrue(errors.contains(.targetAssetMalformed("ETH.")))
    }

    // MARK: - same-asset (source == target)

    func testSameSourceAndTargetAssetIsRejected() {
        let errors = validateLimitSwapInputs(.valid(sourceAsset: "BTC.BTC", targetAsset: "BTC.BTC"))
        XCTAssertTrue(errors.contains(.sourceEqualsTarget("BTC.BTC")))
    }

    func testSameAssetIsRejectedCaseInsensitively() {
        let errors = validateLimitSwapInputs(.valid(sourceAsset: "btc.btc", targetAsset: "BTC.BTC"))
        XCTAssertTrue(errors.contains(where: { if case .sourceEqualsTarget = $0 { return true } else { return false } }))
    }

    func testDistinctAssetsAreNotFlaggedAsSameAsset() {
        let errors = validateLimitSwapInputs(.valid(sourceAsset: "BTC.BTC", targetAsset: "ETH.ETH"))
        XCTAssertFalse(errors.contains(where: { if case .sourceEqualsTarget = $0 { return true } else { return false } }))
    }

    // MARK: - Multiple errors aggregated

    func testMultipleProblemsAreAllReported() {
        let inputs = LimitSwapInputs(
            sourceAsset: "BTC",
            sourceAmount: 0,
            sourceDecimals: 8,
            targetAsset: "ETH",
            destAddress: "",
            targetPrice: 0,
            expiryHours: 7,
            affiliate: "vi",
            affiliateBps: "50"
        )
        let errors = validateLimitSwapInputs(inputs)
        XCTAssertTrue(errors.contains(.sourceAmountNotPositive))
        XCTAssertTrue(errors.contains(.targetPriceNotPositive))
        XCTAssertTrue(errors.contains(.expiryHoursUnsupported(7)))
        XCTAssertTrue(errors.contains(.destAddressEmpty))
        XCTAssertTrue(errors.contains(.sourceAssetMalformed("BTC")))
        XCTAssertTrue(errors.contains(.targetAssetMalformed("ETH")))
    }
}

// MARK: - Test fixture builder

private extension LimitSwapInputs {

    static func valid(
        sourceAsset: String = "BTC.BTC",
        sourceAmount: BigInt = 100_000_000,
        sourceDecimals: Int = 8,
        targetAsset: String = "ETH.ETH",
        destAddress: String = "0x1234567890abcdef1234567890abcdef12345678",
        targetPrice: Decimal = 16,
        expiryHours: Int = 24,
        affiliate: String = "vi",
        affiliateBps: String = "50"
    ) -> LimitSwapInputs {
        LimitSwapInputs(
            sourceAsset: sourceAsset,
            sourceAmount: sourceAmount,
            sourceDecimals: sourceDecimals,
            targetAsset: targetAsset,
            destAddress: destAddress,
            targetPrice: targetPrice,
            expiryHours: expiryHours,
            affiliate: affiliate,
            affiliateBps: affiliateBps
        )
    }
}
