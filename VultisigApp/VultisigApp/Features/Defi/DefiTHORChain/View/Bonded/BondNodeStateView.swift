//
//  BondNodeStateView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 17/10/2025.
//

import SwiftUI

struct BondNodeStateView: View {
    let state: BondNodeState
    
    var body: some View {
        Text(title)
            .foregroundStyle(color)
            .font(Theme.fonts.caption12)
    }
    
    var title: String {
        switch state {
        case .active:
            "active".localized
        case .churnedOut:
            "churnedOut".localized
        }
    }
    
    var color: Color {
        switch state {
        case .active:
            Theme.colors.alertSuccess
        case .churnedOut:
            Theme.colors.alertWarning
        }
    }
}

#Preview {
    VStack {
        BondNodeStateView(state: .active)
        BondNodeStateView(state: .churnedOut)
    }
    .frame(maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
