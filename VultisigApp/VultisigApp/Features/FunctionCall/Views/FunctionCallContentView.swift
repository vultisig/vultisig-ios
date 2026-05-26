//
//  FunctionCallContentView.swift
//  VultisigApp
//
//  Dispatch surface for `FunctionCallInstance` sub-models. Switches
//  exhaustively over the enum to render the concrete per-sub-model
//  `XxxFormView`. After PR3 (C-2e), every sub-model has a typed form
//  view — no more `AnyView` fallback.
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
            AddThorLPFormView(model: model, selectedCoin: $selectedCoin)
        case .securedAsset(let model):
            SecuredAssetFormView(model: model, selectedCoin: $selectedCoin)
        case .withdrawSecuredAsset(let model):
            WithdrawSecuredAssetFormView(model: model, selectedCoin: $selectedCoin)
        }
    }
}
