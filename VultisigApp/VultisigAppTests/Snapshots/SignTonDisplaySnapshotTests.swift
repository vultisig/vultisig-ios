//
//  SignTonDisplaySnapshotTests.swift
//  VultisigAppTests
//

import SnapshotTesting
import SwiftUI
import XCTest

@testable import VultisigApp

@MainActor
final class SignTonDisplaySnapshotTests: XCTestCase {

    private let coinTicker = "TON"
    private let coinDecimals = 9

    override func setUpWithError() throws {
        // Set to true to generate/update reference images, then back to false
        // isRecording = true
    }

    func testSingleMessage() {
        let view = SignTonDisplayView(
            signTon: SignTon(tonMessages: [
                TonMessage(
                    to: "EQCIcjES4cQET0z6nRixZ0MdvTB4u3_8triztLSrIIrDkpgJ",
                    amount: "1000000000"
                )
            ]),
            coinTicker: coinTicker,
            coinDecimals: coinDecimals
        )
        .frame(width: 361)
        .padding()
        .background(Color.black)
        .colorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.95,
                layout: .device(config: .iPhone16Pro)
            )
        )
    }

    func testMultipleMessagesWithStateInitAndPayload() {
        let view = SignTonDisplayView(
            signTon: SignTon(tonMessages: [
                TonMessage(
                    to: "EQCIcjES4cQET0z6nRixZ0MdvTB4u3_8triztLSrIIrDkpgJ",
                    amount: "1500000000",
                    payload: "te6cckEBAQEADgAAGAAAAABIZWxsbw=="
                ),
                TonMessage(
                    to: "EQBvW8Z5huBkMJYdnfAEM5JqTNkuWX3diqYENkWsIL0XggGG",
                    amount: "2000000000",
                    stateInit: "te6ccgECBgEAAWoAART/APSk"
                ),
                TonMessage(
                    to: "EQDtFpEwcFAEcRe5mLVh2N6C0x-_hJEM7W61_JLnSF74p1Oe",
                    amount: "500000000",
                    payload: "te6cckEBAQEADgAAGAAAAABIZWxsbw==",
                    stateInit: "te6ccgECBgEAAWoAART/APSk"
                )
            ]),
            coinTicker: coinTicker,
            coinDecimals: coinDecimals
        )
        .frame(width: 361)
        .padding()
        .background(Color.black)
        .colorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.95,
                layout: .device(config: .iPhone16Pro)
            )
        )
    }

    func testFourMessagesMaxCapacity() {
        let addresses = [
            "EQCIcjES4cQET0z6nRixZ0MdvTB4u3_8triztLSrIIrDkpgJ",
            "EQBvW8Z5huBkMJYdnfAEM5JqTNkuWX3diqYENkWsIL0XggGG",
            "EQDtFpEwcFAEcRe5mLVh2N6C0x-_hJEM7W61_JLnSF74p1Oe",
            "EQAvlWFDxGF2lXm67y4yzC17wYKD9A0guwPkMs1gOsM__NOT"
        ]
        let messages = addresses.enumerated().map { index, addr in
            TonMessage(to: addr, amount: "\((index + 1) * 100_000_000)")
        }

        let view = SignTonDisplayView(
            signTon: SignTon(tonMessages: messages),
            coinTicker: coinTicker,
            coinDecimals: coinDecimals
        )
        .frame(width: 361)
        .padding()
        .background(Color.black)
        .colorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.95,
                layout: .device(config: .iPhone16Pro)
            )
        )
    }
}
