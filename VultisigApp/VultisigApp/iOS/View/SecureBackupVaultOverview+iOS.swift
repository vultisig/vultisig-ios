//
//  SecureBackupVaultOverview+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-01.
//

#if os(iOS)
import SwiftUI

extension SecureBackupVaultOverview {
    var container: some View {
        content
            .navigationBarBackButtonHidden(true)
    }

    var textTabView: some View {
        text
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
    }

    var button: some View {
        nextButton
            .padding(.horizontal, 40)
            .padding(.bottom, 100)
    }

    var animation: some View {
        animationVM?.view()
            .offset(y: -80)
    }

    var text: some View {
        TabView(selection: $tabIndex) {
            ForEach(0..<totalTabCount, id: \.self) { index in
                VStack {
                    Spacer()
                    OnboardingTextCard(
                        index: index,
                        textPrefix: "SecureVaultOverview",
                        deviceCount: tabIndex==0 ? "\(vault.signers.count)" : nil
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
