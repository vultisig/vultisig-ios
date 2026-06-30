//
//  QBTCClaimViewModelTests.swift
//  VultisigAppTests
//
//  Covers the resolver wiring in `QBTCClaimViewModel.load()` (#4679): a
//  non-quantum vault can derive BTC but not QBTC, so the claim blocks on
//  `.missingCoin` — the only genuine derivation failure — before any
//  network call is made.
//

@testable import VultisigApp
import XCTest

@MainActor
final class QBTCClaimViewModelTests: XCTestCase {

    private static let pubKeyECDSA = "023e4b76861289ad4528b33c2fd21b3a5160cd37b3294234914e21efb6ed4a452b"
    private static let hexChainCode = "c9b189a8232b872b8d9ccd867d0db316dd10f56e729c310fe072adf5fd204ae7"

    /// A DKLS vault (so `supportsQbtcClaim` is true) that is NOT
    /// quantum-capable — it has no MLDSA-44 key, so QBTC can't be derived.
    func testBlocksOnMissingQbtcCoinForNonQuantumVault() async {
        let vault = Vault(name: "v")
        vault.pubKeyECDSA = Self.pubKeyECDSA
        vault.hexChainCode = Self.hexChainCode
        vault.publicKeyMLDSA44 = nil

        let viewModel = QBTCClaimViewModel(vault: vault)
        await viewModel.load()

        XCTAssertEqual(
            viewModel.state,
            .blocked(reason: .missingCoin(chainName: Chain.qbtc.name)),
            "A non-quantum vault must block on the QBTC coin it cannot derive"
        )
        XCTAssertNil(viewModel.resolvedCoins)
    }
}
