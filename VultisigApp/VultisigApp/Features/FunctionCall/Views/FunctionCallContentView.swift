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
        // `FunctionCallInstance` has no cases left: every operation is on
        // `Features/FunctionTransaction/`. Nothing constructs this view any
        // more; it goes with the rest of the legacy shell.
        EmptyView()
    }
}
