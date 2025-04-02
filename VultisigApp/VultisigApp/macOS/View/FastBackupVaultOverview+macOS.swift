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
}
#endif
