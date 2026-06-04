//
//  FastVaultMldsaInviteTests.swift
//  VultisigApp
//
//  Pins the rule that decides the `mldsa` flag on the FastVault sign
//  invite. `KeysignDiscoveryViewModel.startKeysignSession` passes
//  `isMldsa: coin.chain.signingKeyType == .MLDSA` to
//  `FastVaultService.sign`. If that flag is dropped (or a new ML-DSA
//  chain forgets to set `signingKeyType`), Vultiserver silently runs an
//  EdDSA keysign while the device runs the ML-DSA (Dilithium) round —
//  the server-side MPC never starts and the device polls the relay for
//  inbound messages forever. QBTC send / staking is the only flow that
//  exercises a real ML-DSA MPC keysign with the server today, so this
//  rule is the load-bearing guard against that stall.
//

@testable import VultisigApp
import XCTest

final class FastVaultMldsaInviteTests: XCTestCase {

    /// The chains that must invite Vultiserver with `mldsa: true`. Every
    /// other chain must leave it `false` (server picks ECDSA / EdDSA via
    /// `is_ecdsa`). When a new ML-DSA chain ships, add it here — the
    /// coverage assertion below mirrors the exact expression the invite
    /// uses, so a missing `signingKeyType == .MLDSA` is caught.
    private static let mldsaChains: Set<Chain> = [.qbtc]

    // MARK: - Rule

    func testMldsaInviteFlagMatchesSigningKeyType() {
        for chain in Chain.allCases {
            let invitesAsMldsa = chain.signingKeyType == .MLDSA
            XCTAssertEqual(
                invitesAsMldsa,
                Self.mldsaChains.contains(chain),
                "Chain.\(chain): FastVault invite mldsa flag (signingKeyType == .MLDSA) = \(invitesAsMldsa), " +
                "but the expected set says \(Self.mldsaChains.contains(chain)). " +
                "If this chain now signs with ML-DSA, add it to `mldsaChains`; " +
                "otherwise its keysign would route the server to ML-DSA and hang."
            )
        }
    }

    // MARK: - Spot checks

    func testQbtcInvitesServerAsMldsa() {
        XCTAssertEqual(Chain.qbtc.signingKeyType, .MLDSA)
    }

    func testSecp256k1ChainDoesNotSetMldsaFlag() {
        XCTAssertNotEqual(Chain.bitcoin.signingKeyType, .MLDSA)
        XCTAssertNotEqual(Chain.thorChain.signingKeyType, .MLDSA)
    }

    func testEdDSAChainDoesNotSetMldsaFlag() {
        XCTAssertNotEqual(Chain.solana.signingKeyType, .MLDSA)
    }
}
