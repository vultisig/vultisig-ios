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

    // MARK: - expiry range
    //
    // Was a three-value whitelist ({12, 24, 72} hours). Now a RANGE, because the
    // expiry is a duration the user picks: the ceiling is THORChain's (clamped
    // silently on-chain, so rejecting here is what keeps the memo honest) and the
    // floor is the app's own.

    func testPresetExpiriesAreAccepted() {
        for hours in [12, 24, 72] {
            let errors = validateLimitSwapInputs(.valid(expiryBlocks: THORChainConstants.blocks(forHours: hours)))
            XCTAssertFalse(errors.contains(where: isExpiryError), "\(hours)h should be accepted")
        }
    }

    func testArbitraryDurationInsideTheRangeIsAccepted() {
        // The point of the feature: 6h and 90m used to be rejected outright.
        for minutes in [90, 6 * 60, 37 * 60, 71 * 60 + 59] {
            let errors = validateLimitSwapInputs(.valid(expiryBlocks: THORChainConstants.blocks(forMinutes: minutes)))
            XCTAssertFalse(errors.contains(where: isExpiryError), "\(minutes)m should be accepted")
        }
    }

    func testExpiryAtExactlyTheBoundsIsAccepted() {
        let atFloor = validateLimitSwapInputs(.valid(expiryBlocks: THORChainConstants.minLimitSwapAgeBlocks))
        XCTAssertFalse(atFloor.contains(where: isExpiryError))

        let atCeiling = validateLimitSwapInputs(.valid(expiryBlocks: THORChainConstants.defaultLimitSwapMaxAgeBlocks))
        XCTAssertFalse(atCeiling.contains(where: isExpiryError))
    }

    func testExpiryBelowTheFloorIsRejected() {
        let blocks = THORChainConstants.minLimitSwapAgeBlocks - 1
        let errors = validateLimitSwapInputs(.valid(expiryBlocks: blocks))
        XCTAssertTrue(errors.contains(.expiryOutOfRange(
            blocks: blocks,
            minBlocks: THORChainConstants.minLimitSwapAgeBlocks,
            maxBlocks: THORChainConstants.defaultLimitSwapMaxAgeBlocks
        )))
    }

    func testExpiryAboveTheCeilingIsRejected() {
        // THORChain would clamp this silently rather than error, which is exactly
        // why the app has to reject it: otherwise the memo says one thing and the
        // queue enforces another.
        let blocks = THORChainConstants.defaultLimitSwapMaxAgeBlocks + 1
        let errors = validateLimitSwapInputs(.valid(expiryBlocks: blocks))
        XCTAssertTrue(errors.contains(.expiryOutOfRange(
            blocks: blocks,
            minBlocks: THORChainConstants.minLimitSwapAgeBlocks,
            maxBlocks: THORChainConstants.defaultLimitSwapMaxAgeBlocks
        )))
    }

    func testCeilingFollowsTheInjectedMimirValue() {
        // A raised on-chain cap must widen the accepted range on its own, rather
        // than being rejected by a constant baked in at build time.
        let raised = THORChainConstants.defaultLimitSwapMaxAgeBlocks * 2
        let errors = validateLimitSwapInputs(
            .valid(expiryBlocks: raised),
            maxExpiryBlocks: raised
        )
        XCTAssertFalse(errors.contains(where: isExpiryError))
    }

    private func isExpiryError(_ error: LimitSwapValidationError) -> Bool {
        if case .expiryOutOfRange = error { return true }
        return false
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
            expiryBlocks: THORChainConstants.blocks(forMinutes: 7),
            affiliate: "vi",
            affiliateBps: "50"
        )
        let errors = validateLimitSwapInputs(inputs)
        XCTAssertTrue(errors.contains(.sourceAmountNotPositive))
        XCTAssertTrue(errors.contains(.targetPriceNotPositive))
        XCTAssertTrue(errors.contains(.expiryOutOfRange(
            blocks: THORChainConstants.blocks(forMinutes: 7),
            minBlocks: THORChainConstants.minLimitSwapAgeBlocks,
            maxBlocks: THORChainConstants.defaultLimitSwapMaxAgeBlocks
        )))
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
        expiryBlocks: Int = THORChainConstants.blocks(forHours: 24),
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
            expiryBlocks: expiryBlocks,
            affiliate: affiliate,
            affiliateBps: affiliateBps
        )
    }
}
