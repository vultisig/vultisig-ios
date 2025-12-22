//
//  UpgradeYourVaultView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-11.
//

import SwiftUI
import RiveRuntime

struct UpgradeYourVaultView: View {
    @Binding var showSheet: Bool
    let onUpgrade: () -> Void
    
    @State var animationVM: RiveViewModel? = nil
    
    var body: some View {
        ZStack {
            Background()
            container
        }
        .onAppear {
            setData()
        }
    }
    
    var content: some View {
        VStack(spacing: 0) {
            title
            Spacer()
            animation
            Spacer()
            description
            button
        }
        .padding(36)
    }
    
    var title: some View {
        Text(NSLocalizedString("upgradeYourVault", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodyLMedium)
    }
    
    var animation: some View {
        animationVM?.view()
    }
    
    var description: some View {
        Group {
            Text(NSLocalizedString("upgradeYourVaultTitle1", comment: ""))
                .foregroundColor(Theme.colors.textPrimary) +
            Text(NSLocalizedString("upgradeYourVaultTitle2", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString("upgradeYourVaultTitle3", comment: ""))
                .foregroundColor(Theme.colors.textPrimary)
        }
        .multilineTextAlignment(.center)
        .font(Theme.fonts.title1)
    }
    
    var button: some View {
        PrimaryButton(title: "upgradeNow") {
            showSheet = false
            onUpgrade()
        }
        .frame(width: 180)
        .padding(.vertical, 36)
    }
    
    private func setData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            animationVM = RiveViewModel(fileName: "upgrade_animation", autoPlay: true)
        }
    }
}

#Preview {
    UpgradeYourVaultView(
        showSheet: .constant(true),
        onUpgrade: {}
    )
}
