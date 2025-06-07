//
//  AllDevicesUpgradeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-11.
//

import SwiftUI
import RiveRuntime

struct AllDevicesUpgradeView: View {
    let vault: Vault
    
    @State var animationVM: RiveViewModel? = nil
    
    var body: some View {
        ZStack {
            Background()
            content
        }
        .onAppear {
            setData()
        }
    }
    
    var animation: some View {
        animationVM?.view()
    }
    
    var description: some View {
        Group {
            Text(NSLocalizedString("allDevicesUpgradeTitle1", comment: ""))
                .foregroundColor(.neutral0) +
            Text(NSLocalizedString("allDevicesUpgradeTitle2", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString("allDevicesUpgradeTitle3", comment: ""))
                .foregroundColor(.neutral0)
        }
        .multilineTextAlignment(.center)
        .font(.body28BrockmannMedium)
    }
    
    var button: some View {
        NavigationLink(destination: {
            VaultShareBackupsView(vault: vault)
        }, label: {
            label
        })
        .padding(.vertical, 36)
    }
    
    var label: some View {
        FilledButton(title: "next")
            .frame(width: 100)
    }
    
    private func setData() {
        animationVM = RiveViewModel(fileName: "all_devices_animation", autoPlay: true)
    }
}

#Preview {
    AllDevicesUpgradeView(vault: Vault.example)
}
