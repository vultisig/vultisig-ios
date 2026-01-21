//
//  FastBackupVaultOverview+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-02-01.
//

#if os(iOS)
import SwiftUI

extension FastBackupVaultOverview {
    var container: some View {
        content
            .navigationBarBackButtonHidden(true)
    }
    
    var textTabView: some View {
        text
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .onAppear {
                  UIScrollView.appearance().isScrollEnabled = false
            }
    }
    
    var button: some View {
        nextButton
            .padding(.horizontal, 40)
            .padding(.bottom, 100)
    }
    
    var text: some View {
        TabView(selection: $tabIndex) {
            ForEach(0..<totalTabCount, id: \.self) { index in
                VStack {
                    Spacer()
                    OnboardingTextCard(
                        index: index,
                        textPrefix: "FastVaultOverview",
                        deviceCount: tabIndex==0 ? "\(vault.signers.count)" : nil
                    )
                }
            }
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
        .offset(y: -100)
    }
}
#endif
