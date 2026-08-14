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
        case .custom(let model):
            CustomFormView(model: model, selectedCoin: $selectedCoin)
        case .cosmosIBC(let model):
            CosmosIBCFormView(model: model, selectedCoin: $selectedCoin)
        }
    }
}
