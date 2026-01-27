//
//  TronRouter.swift
//  VultisigApp
//
//  Created for TRON Freeze/Unfreeze integration
//

import SwiftUI

struct TronRouter {
    private let viewBuilder = TronRouteBuilder()

    @ViewBuilder
    func build(_ route: TronRoute) -> some View {
        switch route {
        case .main(let vault):
            viewBuilder.buildMainScreen(vault: vault)
        case .freeze(let vault):
            viewBuilder.buildFreezeScreen(vault: vault)
        case .unfreeze(let vault, let model):
            viewBuilder.buildUnfreezeScreen(vault: vault, model: model)
        }
    }
}
