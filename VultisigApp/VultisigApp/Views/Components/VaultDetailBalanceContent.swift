//
//  VaultDetailBalanceContent.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI

struct VaultDetailBalanceContent: View {
    let vault: Vault
    @Binding var showBalance: Bool
    
    var body: some View {
        HStack(spacing: 18) {
            content
            hideButton
        }
        .frame(maxWidth: .infinity)
        .offset(x: 32)
        .background(Color.backgroundBlue)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
    
    var content: some View {
        Text(vault.coins.totalBalanceInFiatString)
            .font(.title32MenloBold)
            .foregroundColor(.neutral0)
            .padding(.top, 10)
            .multilineTextAlignment(.center)
            .padding(.horizontal, showBalance ? 12 : 0)
            .redacted(reason: showBalance ? .placeholder : [])
    }
    
    var hideButton: some View {
        VStack {
            Button {
                withAnimation {
                    showBalance.toggle()
                }
            } label: {
                Label("", systemImage: showBalance ? "eye": "eye.slash")
                    .labelsHidden()
                    .foregroundColor(.neutral0)
                    .font(.body16Menlo)
            }
            .contentTransition(.symbolEffect(.replace))
        }
        .font(.largeTitle)
        .offset(y: 3)
    }
}

#Preview {
    VaultDetailBalanceContent(
        vault: Vault.example,
        showBalance: .constant(false)
    )
}