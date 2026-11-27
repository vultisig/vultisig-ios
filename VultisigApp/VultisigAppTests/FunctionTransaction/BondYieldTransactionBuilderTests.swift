//
//  BondYieldTransactionBuilderTests.swift
//  VultisigAppTests
//
//  Expected memos follow the BONDYIELD examples in
//  https://dev.thorchain.org/concepts/memos.html
//

@testable import VultisigApp
import XCTest

final class BondYieldTransactionBuilderTests: XCTestCase {

    private static let node = "thor19m4kqulyqvya339jfja84h6qp8tkjgxuxa4n4a"
    private static let vault = FunctionActionFixture.thorAddress

    private func builder(_ percentage: Int) -> BondYieldTransactionBuilder? {
        BondYieldTransactionBuilder(
            coin: FunctionActionFixture.makeRUNE(),
            nodeAddress: Self.node,
            payoutPercentage: percentage
        )
    }

    func testPaysTheShareOutToTheVaultInBasisPoints() {
        XCTAssertEqual(builder(40)?.memo, "BONDYIELD:\(Self.node):4000:\(Self.vault)")
        XCTAssertEqual(builder(1)?.memo, "BONDYIELD:\(Self.node):100:\(Self.vault)")
        XCTAssertEqual(builder(100)?.memo, "BONDYIELD:\(Self.node):10000:\(Self.vault)")
    }

    func testZeroDisablesPayoutsWithoutATarget() {
        XCTAssertEqual(builder(0)?.memo, "BONDYIELD:\(Self.node):0")
    }

    func testAttachesNoFundsAndSignsAsADeposit() throws {
        let builder = try XCTUnwrap(builder(50))
        XCTAssertEqual(builder.amount, "0")
        XCTAssertEqual(builder.toAddress, "")
        XCTAssertFalse(builder.memoFunctionDictionary.allItems().isEmpty)
    }

    func testRejectsAPercentageOutsideZeroToOneHundred() {
        XCTAssertNil(builder(-1))
        XCTAssertNil(builder(101))
    }
}
