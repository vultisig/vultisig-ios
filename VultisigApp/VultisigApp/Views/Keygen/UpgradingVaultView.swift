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
    
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    
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
            .foregroundColor(.alertTurquoise)
            .opacity(0.05)
            .blur(radius: 20)
    }
    
    var animation: some View {
        loadingAnimationVM?.view()
            .frame(width: 24, height: 24)
    }
    
    var title: some View {
        Text(NSLocalizedString("upgradingVault", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body22BrockmannMedium)
    }
    
    var appVersion: some View {
        Text("Version \(version ?? "1").\(build ?? "1")")
            .font(.body12BrockmannMedium)
            .foregroundColor(.extraLightGray)
            .padding(.bottom, 30)
    }
    
    private func setData() {
        loadingAnimationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
    }
}

#Preview {
    UpgradingVaultView()
}
