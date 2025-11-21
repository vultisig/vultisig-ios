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
        case .whitelisted:
            return "whitelisted".localized
        case .standby:
            return "standby".localized
        case .ready:
            return "ready".localized
        case .active:
            return "active".localized
        case .disabled:
            return "disabled".localized
        case .unknown:
            return "unknown".localized
        }
    }

    var color: Color {
        switch state {
        case .active:
            Theme.colors.alertSuccess
        case .ready:
            Theme.colors.alertSuccess
        case .standby:
            Theme.colors.alertWarning
        case .whitelisted:
            Theme.colors.alertWarning
        case .disabled:
            Theme.colors.alertWarning
        case .unknown:
            Theme.colors.alertWarning
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        BondNodeStateView(state: .whitelisted)
        BondNodeStateView(state: .standby)
        BondNodeStateView(state: .ready)
        BondNodeStateView(state: .active)
        BondNodeStateView(state: .disabled)
    }
    .padding()
    .frame(maxHeight: .infinity)
    .background(Theme.colors.bgPrimary)
}
