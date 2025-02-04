//
//  SecureBackupVaultOverview+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-01.
//

#if os(macOS)
import SwiftUI

extension SecureBackupVaultOverview {
    var container: some View {
        content
    }
    
    var textTabView: some View {
        text
    }
    
    var button: some View {
        HStack {
            if tabIndex != 0 {
                prevButton
            }
            
            nextButton
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 50)
    }
    
    var prevButton: some View {
        Button {
            prevTapped()
        } label: {
            FilledButton(icon: "chevron.left")
        }
        .buttonStyle(PlainButtonStyle())
        .background(Color.clear)
        .frame(width: 80)
    }
    
    private func prevTapped() {
        guard tabIndex>0 else {
            return
        }
        
        withAnimation {
            tabIndex-=1
        }
    }
}
#endif
