//
//  FastBackupVaultOverview+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-01.
//

#if os(macOS)
import SwiftUI

extension FastBackupVaultOverview {
    var container: some View {
        content
    }
    
    var textTabView: some View {
        text
    }
    
    var button: some View {
        nextButton
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
    }
    
    var text: some View {
        VStack {
            Spacer()
            OnboardingTextCard(
                index: tabIndex,
                textPrefix: "FastVaultOverview",
                deviceCount: tabIndex==0 ? "\(vault.signers.count)" : nil
            )
        }
        .frame(maxWidth: .infinity)
    }
    
    var animation: some View {
        ZStack {
            if tabIndex>2 {
                backupVaultAnimationVM?.view()
            } else {
                animationVM?.view()
            }
        }
        .scaleEffect(0.7)
        .offset(y: -60)
    }
}
#endif
