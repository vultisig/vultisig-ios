//
//  FunctionCallContentView.swift
//  VultisigApp
//
//  C-2a foundation shell — dispatches over `FunctionCallInstance` to the
//  per-sub-model `XxxFormView` once they exist. Each case currently returns
//  `EmptyView()`; C-2b → C-2e fill in the real form views one batch at a
//  time. The exhaustive `switch` makes adding a new `FunctionCallInstance`
//  case a compile error here until a corresponding view branch is added.
//
//  The legacy `fnCallInstance?.view` dispatch in `FunctionCallDetailsScreen`
//  still drives the actual UI during C-2a; this view is referenced but
//  unused until C-2b lands the first real sub-model views.
//

import SwiftUI

struct FunctionCallContentView: View {
    let instance: FunctionCallInstance
    @Binding var selectedCoin: Coin

    var body: some View {
        switch instance {
        case .rebond:
            EmptyView()
        case .bondMaya:
            EmptyView()
        case .unbondMaya:
            EmptyView()
        case .leave:
            EmptyView()
        case .custom:
            EmptyView()
        case .vote:
            EmptyView()
        case .stake:
            EmptyView()
        case .unstake:
            EmptyView()
        case .cosmosIBC:
            EmptyView()
        case .merge:
            EmptyView()
        case .unmerge:
            EmptyView()
        case .theSwitch:
            EmptyView()
        case .addThorLP:
            EmptyView()
        case .securedAsset:
            EmptyView()
        case .withdrawSecuredAsset:
            EmptyView()
        }
    }
}
