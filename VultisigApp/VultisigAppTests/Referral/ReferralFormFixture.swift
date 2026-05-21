//
//  ReferralFormFixture.swift
//  VultisigAppTests
//
//  Test fixtures for the `@Observable` Referral form VMs. Mirrors
//  `SendFormFixture` for the Send pilot — builds VM instances with sensible
//  defaults plus a closure for per-test overrides.
//

import BigInt
import Foundation
@testable import VultisigApp

enum ReferralFormFixture {

    /// Build a `ReferralDetailsViewModel` for the create flow with a mock
    /// interactor and a vault holding `nativeCoin` if provided. The vault's
    /// native coin balance defaults to `100 RUNE` so the gas-affordability
    /// path is satisfied unless the test deliberately overrides it.
    @MainActor
    static func makeCreateVM(
        rune: Coin = makeRune(),
        thornameDetails: THORName? = nil,
        currentBlockheight: UInt64 = 0,
        interactor: SendInteractor? = nil,
        savedReferralCode: String? = nil,
        overrides: (ReferralDetailsViewModel) -> Void = { _ in }
    ) -> ReferralDetailsViewModel {
        let vault = makeVault(coins: [rune], savedReferralCode: savedReferralCode)
        let vm = ReferralDetailsViewModel(
            vault: vault,
            thornameDetails: thornameDetails,
            currentBlockheight: currentBlockheight,
            interactor: interactor ?? MockSendInteractor(),
            saveReferralCode: { _ in }
        )
        overrides(vm)
        return vm
    }

    /// Build an `EditReferralDetailsViewModel` for the edit flow. The
    /// `thornameDetails` argument is required by the type's invariants.
    @MainActor
    static func makeEditVM(
        rune: Coin = makeRune(),
        thornameDetails: THORName = makeThorname(),
        currentBlockHeight: UInt64 = 0,
        interactor: SendInteractor? = nil,
        overrides: (EditReferralDetailsViewModel) -> Void = { _ in }
    ) -> EditReferralDetailsViewModel {
        let vault = makeVault(coins: [rune])
        let vm = EditReferralDetailsViewModel(
            nativeCoin: rune,
            vault: vault,
            thornameDetails: thornameDetails,
            currentBlockHeight: currentBlockHeight,
            interactor: interactor ?? MockSendInteractor(),
            addCoinIfNeeded: { _, _ in nil }
        )
        overrides(vm)
        return vm
    }

    // MARK: - Builders

    static func makeRune(rawBalance: String = "10000000000") -> Coin {
        // 10000000000 raw = 100 RUNE (8 decimals)
        SendFormFixture.makeCoin(.thorChain, ticker: "RUNE", decimals: 8, isNative: true, rawBalance: rawBalance)
    }

    static func makeVault(
        localPartyID: String = "test-device-123",
        coins: [Coin] = [],
        savedReferralCode: String? = nil
    ) -> Vault {
        let vault = SendFormFixture.makeVault(localPartyID: localPartyID, coins: coins)
        if let savedReferralCode {
            vault.referralCode = ReferralCode(code: savedReferralCode, vault: vault)
        }
        return vault
    }

    /// Construct a minimal `THORName` with sensible defaults. Tests override
    /// fields they care about via the closure.
    static func makeThorname(
        name: String = "TEST",
        expireBlockHeight: UInt64 = 10_000_000,
        preferredAsset: String = "THOR.RUNE",
        affiliateCollectorRune: String = "0"
    ) -> THORName {
        THORName(
            name: name,
            expireBlockHeight: expireBlockHeight,
            owner: "thor1owner",
            preferredAsset: preferredAsset,
            preferredAssetSwapThresholdRune: "0",
            affiliateCollectorRune: affiliateCollectorRune,
            aliases: []
        )
    }
}
