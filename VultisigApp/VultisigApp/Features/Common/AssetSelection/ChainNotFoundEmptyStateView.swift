//
//  ChainNotFoundEmptyStateView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import SwiftUI

struct ChainNotFoundEmptyStateView: View {
    var body: some View {
        VStack {
            VStack(spacing: 12) {
                Icon(named: "crypto", color: Theme.colors.primaryAccent4, size: 24)
                Text("noChainsFound")
                    .foregroundStyle(Theme.colors.textPrimary)
                    .font(Theme.fonts.subtitle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.colors.bgSurface1))
            Spacer()
        }
    }
}

#Preview {
    ChainNotFoundEmptyStateView()
}
