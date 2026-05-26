//
//  FunctionCallContentView.swift
//  VultisigApp
//
//  Dispatch surface for `FunctionCallInstance` sub-models. Switches
//  exhaustively over the enum to render the concrete per-sub-model
//  `XxxFormView`. The 12 PR2-migrated sub-models bind to their typed
//  `@Bindable` form views; the 3 heavy sub-models (AddThorLP,
//  SecuredAsset, WithdrawSecuredAsset) still go through the legacy
//  `AnyView` dispatch until PR3 migrates them.
//

import SwiftUI

struct FunctionCallContentView: View {
    let instance: FunctionCallInstance
    @Binding var selectedCoin: Coin

    var body: some View {
        switch instance {
        case .rebond(let model):
            ReBondFormView(model: model, coin: selectedCoin)
        case .bondMaya(let model):
            BondMayaFormView(model: model, coin: selectedCoin)
        case .unbondMaya(let model):
            UnbondMayaFormView(model: model, coin: selectedCoin)
        case .leave(let model):
            LeaveFormView(model: model, selectedCoin: $selectedCoin)
        case .custom(let model):
            CustomFormView(model: model, selectedCoin: $selectedCoin)
        case .vote(let model):
            VoteFormView(model: model, coin: selectedCoin)
        case .stake(let model):
            StakeFormView(model: model, selectedCoin: $selectedCoin)
        case .unstake(let model):
            UnstakeFormView(model: model, coin: selectedCoin)
        case .cosmosIBC(let model):
            CosmosIBCFormView(model: model, selectedCoin: $selectedCoin)
        case .merge(let model):
            CosmosMergeFormView(model: model, selectedCoin: $selectedCoin)
        case .unmerge(let model):
            CosmosUnmergeFormView(model: model, selectedCoin: $selectedCoin)
        case .theSwitch(let model):
            CosmosSwitchFormView(model: model, coin: selectedCoin)
        case .addThorLP(let model):
            // PR3 (C-2e) migrates this sub-model. Until then, fall back
            // to the legacy `AnyView` body so the LP add flow keeps
            // working without the data-side rewrite landing.
            model.getView()
        case .securedAsset(let model):
            model.getView()
        case .withdrawSecuredAsset(let model):
            model.getView()
        }
    }
}
