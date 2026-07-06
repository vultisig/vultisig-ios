//
//  FunctionCallContentViewTests.swift
//  VultisigAppTests
//
//  View-smoke + dispatch-exhaustiveness coverage for
//  `FunctionCallContentView`. Instantiates each migrated sub-model
//  with canonical inputs and exercises a render of the dispatched
//  view — surfaces "forgot to add a case" regressions even though
//  Swift's enum exhaustiveness catches the same class of bugs at
//  compile time.
//

import SwiftUI
import XCTest
@testable import VultisigApp

@MainActor
final class FunctionCallContentViewTests: XCTestCase {

    func testDispatchExhaustivenessAcrossMigratedSubModels() {
        let rune = FunctionCallFixture.makeRUNE()
        let vault = FunctionCallFixture.makeVault(coins: [rune, FunctionCallFixture.makeRUJI(), FunctionCallFixture.makeATOM(), FunctionCallFixture.makeKUJI()])

        let migrated: [FunctionCallInstance] = [
            .rebond(FunctionCallReBond()),
            .bondMaya(FunctionCallBondMayaChain(assets: [])),
            .unbondMaya(FunctionCallUnbondMayaChain(assets: [])),
            .leave(FunctionCallLeave()),
            .custom(FunctionCallCustom(coin: rune, vault: vault)),
            .vote(FunctionCallVote()),
            .cosmosIBC(FunctionCallCosmosIBC(coin: FunctionCallFixture.makeKUJI(), vault: vault)),
            .merge(FunctionCallCosmosMerge(coin: rune, vault: vault)),
            .unmerge(FunctionCallCosmosUnmerge(coin: FunctionCallFixture.makeRUJI(), vault: vault)),
            .theSwitch(FunctionCallCosmosSwitch(coin: FunctionCallFixture.makeATOM(), vault: vault)),
            .addThorLP(FunctionCallAddThorLP(coin: rune, vault: vault)),
            .securedAsset(FunctionCallSecuredAsset(coin: rune, vault: vault)),
            .withdrawSecuredAsset(FunctionCallWithdrawSecuredAsset(coin: rune, vault: vault))
        ]

        for instance in migrated {
            // Bind a state for the screen's selectedCoin.
            var coin = rune
            let binding = Binding<Coin>(get: { coin }, set: { coin = $0 })
            let view = FunctionCallContentView(instance: instance, selectedCoin: binding)
            // Render the body to confirm no fatal during construction.
            _ = view.body
        }
    }
}
