//
//  TronViewModelTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class TronViewModelTests: XCTestCase {

    func testApplyAccountMapsBalancesAndValidPendingWithdrawals() throws {
        let account = try decode(
            TronAccountResponse.self,
            from: """
            {
              "address": "TTestAddress",
              "balance": 12345678,
              "frozenV2": [
                { "amount": 1000000 },
                { "type": "BANDWIDTH", "amount": 2250000 },
                { "type": "ENERGY", "amount": 3500000 },
                { "type": "ENERGY" }
              ],
              "unfrozenV2": [
                { "unfreeze_amount": 1500000, "unfreeze_expire_time": 1735689600000 },
                { "unfreeze_amount": 750000, "unfreeze_expire_time": 1704067200000 },
                { "unfreeze_amount": 999999 },
                { "unfreeze_expire_time": 1767225600000 }
              ]
            }
            """
        )
        let sut = TronViewModel()
        sut.isLoadingBalance = true

        sut.apply(account: account)

        XCTAssertEqual(sut.availableBalance, try decimal("12.345678"))
        XCTAssertEqual(sut.frozenBandwidthBalance, try decimal("3.25"))
        XCTAssertEqual(sut.frozenEnergyBalance, try decimal("3.5"))
        XCTAssertEqual(sut.unfreezingBalance, try decimal("3.249999"))
        XCTAssertEqual(sut.totalFrozenBalance, try decimal("9.999999"))
        XCTAssertEqual(sut.pendingWithdrawals.count, 2)
        XCTAssertEqual(sut.pendingWithdrawals.map(\.amount), [try decimal("0.75"), try decimal("1.5")])
        XCTAssertEqual(
            sut.pendingWithdrawals.map(\.expirationDate),
            [
                Date(timeIntervalSince1970: 1_704_067_200),
                Date(timeIntervalSince1970: 1_735_689_600)
            ]
        )
        XCTAssertFalse(sut.isLoadingBalance)
    }

    func testApplyAccountWithMissingOptionalFieldsResetsDisplayedValues() throws {
        let account = try decode(TronAccountResponse.self, from: #"{ "address": "TEmpty" }"#)
        let sut = TronViewModel()
        sut.availableBalance = 1
        sut.frozenBandwidthBalance = 2
        sut.frozenEnergyBalance = 3
        sut.unfreezingBalance = 4
        sut.pendingWithdrawals = [
            TronPendingWithdrawal(amount: 5, expirationDate: Date(timeIntervalSince1970: 1))
        ]
        sut.isLoadingBalance = true

        sut.apply(account: account)

        XCTAssertEqual(sut.availableBalance, .zero)
        XCTAssertEqual(sut.frozenBandwidthBalance, .zero)
        XCTAssertEqual(sut.frozenEnergyBalance, .zero)
        XCTAssertEqual(sut.unfreezingBalance, .zero)
        XCTAssertTrue(sut.pendingWithdrawals.isEmpty)
        XCTAssertFalse(sut.isLoadingBalance)
    }

    func testApplyResourceMapsAvailableAndTotalResources() throws {
        let resource = try decode(
            TronAccountResourceResponse.self,
            from: """
            {
              "freeNetUsed": 100,
              "freeNetLimit": 600,
              "NetUsed": 1250,
              "NetLimit": 10000,
              "EnergyUsed": 275000,
              "EnergyLimit": 1000000
            }
            """
        )
        let sut = TronViewModel()
        sut.isLoadingResources = true

        sut.apply(resource: resource)

        XCTAssertEqual(sut.availableBandwidth, 9_250)
        XCTAssertEqual(sut.totalBandwidth, 10_600)
        XCTAssertEqual(sut.availableEnergy, 725_000)
        XCTAssertEqual(sut.totalEnergy, 1_000_000)
        XCTAssertFalse(sut.isLoadingResources)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func decimal(_ value: String) throws -> Decimal {
        try XCTUnwrap(Decimal(string: value))
    }
}
