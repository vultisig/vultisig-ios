//
//  UpgradingVaultView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-16.
//

import SwiftUI
import RiveRuntime

struct UpgradingVaultView: View {
    @State var loadingAnimationVM: RiveViewModel? = nil
    
    var body: some View {
        ZStack {
            shadow
            content
        }
        .onAppear {
            setData()
        }
    }
    
    var content: some View {
        VStack(spacing: 26) {
            Spacer()
            animation
            title
            Spacer()
            appVersion
        }
    }
    
    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(Theme.colors.alertInfo)
            .opacity(0.05)
            .blur(radius: 20)
    }
    
    var animation: some View {
        loadingAnimationVM?.view()
            .frame(width: 24, height: 24)
    }
    
    var title: some View {
        Text(NSLocalizedString("upgradingVault", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.title2)
    }
    
    var appVersion: some View {
        Text(Bundle.main.appVersionString)
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textTertiary)
            .padding(.bottom, 30)
    }
    
    private func setData() {
        loadingAnimationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
    }
}

#Preview {
    UpgradingVaultView()
}
