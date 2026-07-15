//
//  ReshareStartRouteTests.swift
//  VultisigAppTests
//
//  Verifies that "Start reshare" routes on CONFIRMED backend presence. A
//  structural `server-*` signer alone must never force a vault into password
//  validation — a restored or stale vault whose backend vault no longer exists
//  (or any unconfirmed presence: throttled, storage error, or unreachable)
//  would otherwise hit a password screen that can never succeed.
//

import XCTest
@testable import VultisigApp

final class ReshareStartRouteTests: XCTestCase {

    func testConfirmedPresentRoutesToFastVaultPassword() {
        XCTAssertEqual(
            ReshareScreen.startReshareRoute(isBackendConfirmedPresent: true),
            .fastVaultPassword
        )
    }

    func testUnconfirmedPresenceRoutesToPeerDiscovery() {
        // The regression under test: a structural server signer whose backend
        // vault is not confirmed present (missing / throttled / storage error /
        // unreachable, as well as plain secure vaults) must route to peer
        // discovery, never forced password validation.
        XCTAssertEqual(
            ReshareScreen.startReshareRoute(isBackendConfirmedPresent: false),
            .peerDiscovery
        )
    }
}
