//
//  SetupVaultView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftUI
import SwiftData

struct SetupVaultView: View {
    @Binding var presentationStack: [CurrentScreen]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: ApplicationState
    @Query var vaults: [Vault]
    
    var body: some View {
        ZStack {
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("setup", comment: "Setup title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationHelpButton()
            }
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack {
            title
            image
            messageModal
            buttons
        }
        .padding(.top, 30)
    }
    
    var image: some View {
        Image("setupDevicesImage")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(30)
            .frame(maxHeight: .infinity)
    }
    
    var title: some View {
        Text(NSLocalizedString("need3Devices", comment: "Same Wifi instructions"))
            .font(.body16Menlo)
            .foregroundColor(.neutral0)
    }
    
    var messageModal: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi")
                .font(.title30MenloBlack)
                .foregroundColor(.neutral0)
            
            Text(NSLocalizedString("devicesOnSameWifi", comment: "Same Wifi instructions"))
                .font(.body12Menlo)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 250)
    }
    
    var buttons: some View {
        VStack(spacing: 20) {
            startButton
            joinButton
        }
        .padding(40)
    }
    
    var startButton: some View {
        Button {
            startNetwork()
        } label: {
            FilledButton(title: "start")
        }
    }
    
    var joinButton: some View {
        Button {
            joinNetwork()
        } label: {
            OutlineButton(title: "join")
        }
    }
    
    private func startNetwork() {
        let vault = Vault(name: "Vault #\(vaults.count + 1)")
        print("start network")
        self.presentationStack.append(.peerDiscovery(vault: vault, tssType: .Keygen))
    }
    
    private func joinNetwork() {
        let vault = Vault(name: "Vault #\(vaults.count + 1)")
        self.presentationStack.append(.joinKeygen(vault))
    }
}

#Preview {
    SetupVaultView(presentationStack: .constant([]))
        .environmentObject(ApplicationState.shared)
}
