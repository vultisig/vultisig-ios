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
    @Binding var navigationLinkActive: Bool
    
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
            .foregroundColor(.neutral0)
            .font(.body18BrockmannMedium)
    }
    
    var animation: some View {
        animationVM?.view()
    }
    
    var description: some View {
        Group {
            Text(NSLocalizedString("upgradeYourVaultTitle1", comment: ""))
                .foregroundColor(.neutral0) +
            Text(NSLocalizedString("upgradeYourVaultTitle2", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString("upgradeYourVaultTitle3", comment: ""))
                .foregroundColor(.neutral0)
        }
        .multilineTextAlignment(.center)
        .font(.body28BrockmannMedium)
    }
    
    var button: some View {
        PrimaryButton(title: "upgradeNow") {
            showSheet = false
            navigationLinkActive = true
        }
        .frame(width: 160)
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
        navigationLinkActive: .constant(false)
    )
}
