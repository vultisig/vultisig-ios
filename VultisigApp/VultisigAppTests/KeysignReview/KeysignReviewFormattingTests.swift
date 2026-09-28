import XCTest
@testable import VultisigApp

final class KeysignReviewFormattingTests: XCTestCase {
    func testValidatorCommissionKeepsFractionalPercentages() {
        for (rate, percentage) in [("0.0499", "4.99"), ("0.005", "0.5"), ("0.05", "5"), ("0", "0")] {
            let validator = CosmosValidator(
                operatorAddress: "cosmosvaloper1example", moniker: "Validator",
                commission: Decimal(string: rate)!, jailed: false, status: .bonded, votingPower: 1
            )
            let expected = Decimal(string: percentage)!.formatted(.number.precision(.fractionLength(0...2)))
            XCTAssertEqual(
                CosmosStakingValidatorRows.resolve(validator.operatorAddress, in: [validator.operatorAddress: validator]),
                "Validator (\(expected)% \("commission".localized))"
            )
        }
    }
}
