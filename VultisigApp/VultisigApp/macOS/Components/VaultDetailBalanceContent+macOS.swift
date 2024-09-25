//
//  VaultDetailBalanceContent+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-25.
//

#if os(macOS)
import SwiftUI

extension VaultDetailBalanceContent {
    var container: some View {
        content
            .padding(.vertical, 18)
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
        .offset(x: width/2 + 16 , y: 3)
    }
    
    func setData() {
        let balance = vault.coins.totalBalanceInFiatString
        width = balance.widthOfString(usingFont: NSFont.preferredFont(forTextStyle: .title1))*2
        
        redactedText = "$"
        let multiplier = Int(width/25)
        
        for _ in 0..<multiplier {
            redactedText += "*"
        }
    }
}
#endif
