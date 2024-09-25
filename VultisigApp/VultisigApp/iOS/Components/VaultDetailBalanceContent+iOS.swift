//
//  VaultDetailBalanceContent+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-25.
//

#if os(iOS)
import SwiftUI

extension VaultDetailBalanceContent {
    var container: some View {
        content
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
        .offset(x: width/2 + 28 , y: 3)
    }
    
    func setData() {
        let balance = vault.coins.totalBalanceInFiatString
        width = balance.widthOfString(usingFont: UIFont.preferredFont(forTextStyle: .extraLargeTitle))
        
        redactedText = "$"
        let multiplier = Int(width/25)
        
        for _ in 0..<multiplier {
            redactedText += "*"
        }
    }
}
#endif
