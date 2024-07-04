//
//  VaultDetailBalanceContent.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-07.
//

import SwiftUI

struct VaultDetailBalanceContent: View {
    let vault: Vault
    
    @State var width: CGFloat = .zero
    @State var redactedText = ""
    
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    var body: some View {
        ZStack {
            content
            hideButton
        }
        .frame(maxWidth: .infinity)
        .background(Color.backgroundBlue)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
#if os(macOS)
        .padding(.vertical, 18)
#endif
        .onAppear {
            setData()
        }
    }
    
    var content: some View {
        Text(homeViewModel.hideVaultBalance ? redactedText : vault.coins.totalBalanceInFiatString)
            .font(.title32MenloBold)
            .foregroundColor(.neutral0)
            .padding(.top, 10)
            .multilineTextAlignment(.center)
            .frame(width: width)
    }
    
    var hideButton: some View {
        VStack {
            Button {
                withAnimation {
                    homeViewModel.hideVaultBalance.toggle()
                }
            } label: {
                Label("", systemImage: homeViewModel.hideVaultBalance ? "eye.slash" : "eye")
                    .labelsHidden()
                    .foregroundColor(.neutral0)
                    .font(.body16Menlo)
            }
            .contentTransition(.symbolEffect(.replace))
        }
        .font(.largeTitle)
#if os(iOS)
        .offset(x: width/2 + 28 , y: 3)
#elseif os(macOS)
        .offset(x: width/2 + 16 , y: 3)
#endif
    }
    
    private func setData() {
        let balance = vault.coins.totalBalanceInFiatString
#if os(iOS)
        width = balance.widthOfString(usingFont: UIFont.preferredFont(forTextStyle: .extraLargeTitle))
#elseif os(macOS)
        width = balance.widthOfString(usingFont: NSFont.preferredFont(forTextStyle: .title1))*2
#endif
        
        redactedText = "$"
        let multiplier = Int(width/25)
        
        for _ in 0..<multiplier {
            redactedText += "*"
        }
    }
}

#Preview {
    VaultDetailBalanceContent(
        vault: Vault.example
    )
}
