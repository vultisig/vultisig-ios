//
//  TonJettonFeeTests.swift
//  VultisigAppTests
//
//  A jetton transfer attaches TonHelper.defaultJettonFee, not the native
//  defaultFee, so the fee display (which reads BlockChainSpecific.gas/.fee)
//  must branch on jettonAddress or it under-tells the cost on every jetton send.
//

import BigInt
import XCTest
@testable import VultisigApp

final class TonJettonFeeTests: XCTestCase {

    func testNativeTonGasUsesDefaultFee() {
        let specific = BlockChainSpecific.Ton(
            sequenceNumber: 1,
            expireAt: 0,
            bounceable: true,
            sendMaxAmount: false,
            jettonAddress: "",
            isActiveDestination: true
        )
        XCTAssertEqual(specific.gas, TonHelper.defaultFee)
        XCTAssertEqual(specific.fee, TonHelper.defaultFee)
    }

    func testJettonTonGasUsesDefaultJettonFee() {
        let specific = BlockChainSpecific.Ton(
            sequenceNumber: 1,
            expireAt: 0,
            bounceable: true,
            sendMaxAmount: false,
            jettonAddress: "EQD-jettonWalletAddressPlaceholder",
            isActiveDestination: true
        )
        XCTAssertEqual(specific.gas, TonHelper.defaultJettonFee)
        XCTAssertEqual(specific.fee, TonHelper.defaultJettonFee)
    }
}
