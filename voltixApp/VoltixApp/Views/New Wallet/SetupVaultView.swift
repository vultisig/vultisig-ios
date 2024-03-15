//
//  SetupVaultView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftData
import SwiftUI

struct SetupVaultView: View {
    let tssType: TssType
    @State var vault: Vault? = nil
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
        .onAppear {
            if vault == nil {
                vault = Vault(name: "Vault #\(vaults.count + 1)")
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
            joinKeyshareButton
        }
        .padding(40)
    }
    
    var startButton: some View {
        NavigationLink {
            PeerDiscoveryView(tssType: tssType, vault: vault ?? Vault(name: "New Vault"))
        } label: {
            FilledButton(title: "start")
        }
    }

    var joinKeyshareButton: some View {
        NavigationLink {
            JoinKeygenView(vault: vault ?? Vault(name: "New Vault"))
        } label: {
            OutlineButton(title: "joinKeyshare")
        }
    }
    
    var joinButton: some View {
        NavigationLink {
            JoinKeygenView(vault: vault ?? Vault(name: "New Vault"))
        } label: {
            OutlineButton(title: "join")
        }
    }
}

#Preview {
    SetupVaultView(tssType: .Keygen)
}
