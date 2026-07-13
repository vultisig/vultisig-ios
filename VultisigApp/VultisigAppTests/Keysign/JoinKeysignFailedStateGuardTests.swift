//
//  JoinKeysignFailedStateGuardTests.swift
//  VultisigAppTests
//
//  Pins that a co-signer whose keysign messages failed to prepare stays on the
//  failure screen. `prepareKeysignMessages` rejects an unsupported payload —
//  e.g. a multi-transaction Solana `signAllTransactions` batch (N>1) — by
//  setting `.FailedToStart`, but the deeplink handler then runs
//  `manageQrCodeStates()`. Without the guard that method unconditionally moves
//  a relay payload to `.JoinKeysign`, clobbering the failure and letting the
//  co-signer tap "Join" into the ceremony with no messages to sign. This test
//  fails before the ceremony can be entered.
//

@testable import VultisigApp
import XCTest

@MainActor
final class JoinKeysignFailedStateGuardTests: XCTestCase {

    func testManageQrCodeStatesKeepsFailedToStart() {
        let viewModel = JoinKeysignViewModel()
        // The relay path is the one that would otherwise transition to
        // `.JoinKeysign`; prove the failure survives it.
        viewModel.useVultisigRelay = true
        viewModel.status = .FailedToStart

        viewModel.manageQrCodeStates()

        XCTAssertEqual(
            viewModel.status,
            .FailedToStart,
            "A payload that failed to prepare must not be advanced into the join/ceremony flow"
        )
    }

    func testManageQrCodeStatesStillAdvancesHealthyRelayPayload() {
        let viewModel = JoinKeysignViewModel()
        viewModel.useVultisigRelay = true
        // Default status (.DiscoverSigningMsg) with no blocking payload: the
        // regression guard must not interfere with the normal relay transition.
        viewModel.manageQrCodeStates()

        XCTAssertEqual(viewModel.status, .JoinKeysign)
    }
}
