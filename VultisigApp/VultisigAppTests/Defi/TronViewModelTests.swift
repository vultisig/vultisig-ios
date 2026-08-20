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

    func testClaimableBalanceCountsOnlyExpiredWithdrawals() throws {
        let account = try decode(
            TronAccountResponse.self,
            from: """
            {
              "address": "TTestAddress",
              "unfrozenV2": [
                { "unfreeze_amount": 1500000, "unfreeze_expire_time": 4102444800000 },
                { "unfreeze_amount": 750000, "unfreeze_expire_time": 1704067200000 }
              ]
            }
            """
        )
        let sut = TronViewModel()

        sut.apply(account: account)

        XCTAssertEqual(sut.pendingWithdrawals.count, 2)
        XCTAssertEqual(sut.unfreezingBalance, try decimal("2.25"))
        XCTAssertEqual(sut.claimableBalance, try decimal("0.75"))
        XCTAssertTrue(sut.hasClaimableWithdrawals)
    }

    func testClaimableBalanceIsZeroWhenEveryWithdrawalIsStillLocked() {
        let sut = TronViewModel()
        sut.pendingWithdrawals = [
            TronPendingWithdrawal(amount: 5, expirationDate: Date(timeIntervalSince1970: 4_102_444_800))
        ]

        XCTAssertEqual(sut.claimableBalance, .zero)
        XCTAssertFalse(sut.hasClaimableWithdrawals)
    }

    func testMakeClaimTransactionSweepsExpiredEntriesIntoSelfAddressedStakingSend() throws {
        let trx = SendFormFixture.makeTRX()
        let vault = SendFormFixture.makeVault(coins: [trx])
        vault.fastVaultEligibility = true
        vault.fastVaultEligibilityCheckedAt = Date()
        let sut = TronViewModel()
        sut.pendingWithdrawals = [
            TronPendingWithdrawal(amount: try decimal("0.75"), expirationDate: Date(timeIntervalSince1970: 1_704_067_200)),
            TronPendingWithdrawal(amount: try decimal("1.5"), expirationDate: Date(timeIntervalSince1970: 1_735_689_600)),
            TronPendingWithdrawal(amount: 3, expirationDate: Date(timeIntervalSince1970: 4_102_444_800))
        ]

        let tx = try XCTUnwrap(sut.makeClaimTransaction(vault: vault))

        XCTAssertEqual(tx.coin.ticker, "TRX")
        XCTAssertEqual(tx.fromAddress, trx.address)
        XCTAssertEqual(tx.toAddress, trx.address)
        XCTAssertEqual(tx.amount, "2.25")
        XCTAssertEqual(tx.memo, TronHelper.withdrawExpireUnfreezeMemo)
        XCTAssertTrue(tx.isStakingOperation)
        XCTAssertFalse(tx.sendMaxAmount)
    }

    func testMakeClaimTransactionIsNilForSecureVault() throws {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeTRX()])
        vault.fastVaultEligibility = false
        vault.fastVaultEligibilityCheckedAt = Date()
        let sut = TronViewModel()
        sut.pendingWithdrawals = [
            TronPendingWithdrawal(
                amount: try decimal("0.75"),
                expirationDate: Date(timeIntervalSince1970: 1_704_067_200)
            )
        ]

        XCTAssertFalse(TronViewLogic.canClaimExpiredUnfreezes(vault: vault))
        XCTAssertNil(sut.makeClaimTransaction(vault: vault))
    }

    func testMakeClaimTransactionIsEnabledForFastVault() {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeTRX()])
        vault.fastVaultEligibility = true
        vault.fastVaultEligibilityCheckedAt = Date()

        XCTAssertTrue(TronViewLogic.canClaimExpiredUnfreezes(vault: vault))
    }

    func testMakeClaimTransactionIsNilWhenNothingIsClaimable() {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeTRX()])
        let sut = TronViewModel()

        XCTAssertNil(sut.makeClaimTransaction(vault: vault), "no pending withdrawals")

        sut.pendingWithdrawals = [
            TronPendingWithdrawal(amount: 5, expirationDate: Date(timeIntervalSince1970: 4_102_444_800))
        ]
        XCTAssertNil(sut.makeClaimTransaction(vault: vault), "only locked withdrawals")
    }

    func testMakeClaimTransactionIsNilWithoutTrxCoin() throws {
        let vault = SendFormFixture.makeVault(coins: [SendFormFixture.makeETH()])
        let sut = TronViewModel()
        sut.pendingWithdrawals = [
            TronPendingWithdrawal(amount: try decimal("0.75"), expirationDate: Date(timeIntervalSince1970: 1_704_067_200))
        ]

        XCTAssertNil(sut.makeClaimTransaction(vault: vault))
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private func decimal(_ value: String) throws -> Decimal {
        try XCTUnwrap(Decimal(string: value))
    }
}
