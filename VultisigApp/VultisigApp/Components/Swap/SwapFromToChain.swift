//
//  SwapFromToChain.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-26.
//

import SwiftUI

struct SwapFromToChain: View {
    let chain: Chain?

    var body: some View {
        HStack(spacing: 4) {
            icon
            title
            chevron
        }
    }

    var icon: some View {
        Image(chain?.logo ?? "")
            .resizable()
            .frame(width: 16, height: 16)
    }

    var title: some View {
        Text(chain?.name ?? "")
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
    }

    var chevron: some View {
        Image(systemName: "chevron.down")
            .font(Theme.fonts.caption10)
            .foregroundColor(Theme.colors.textPrimary)
            .cornerRadius(32)
            .bold()
    }
}

#Preview {
    SwapFromToChain(chain: Chain.example)
}
