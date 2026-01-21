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
        IconButton(icon: "chevron-right") {
            prevTapped()
        }
        .frame(width: 80)
        .rotationEffect(.radians(.pi))
    }

    var text: some View {
        VStack {
            Spacer()
            OnboardingTextCard(
                index: tabIndex,
                textPrefix: "SecureVaultOverview",
                deviceCount: tabIndex==0 ? "\(vault.signers.count)" : nil
            )
        }
        .frame(maxWidth: .infinity)
    }

    var animation: some View {
        animationVM?.view()
            .scaleEffect(0.7)
            .offset(y: -60)
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
