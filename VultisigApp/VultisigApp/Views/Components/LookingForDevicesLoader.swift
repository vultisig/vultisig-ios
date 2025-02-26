//
//  LookingForDevicesLoader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-20.
//

import SwiftUI
import RiveRuntime

struct LookingForDevicesLoader: View {
    var tssType: TssType? = nil
    var selectedTab: SetupVaultState? = nil
    
    @State var animationVM: RiveViewModel? = nil
    
    @State var didSwitch = false

    var body: some View {
        ZStack {
            shadow
            content
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cornerRadius(10)
        .shadow(radius: 5)
        .onAppear {
            animationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                didSwitch.toggle()
            }
        }
        .onDisappear {
            animationVM?.stop()
        }
    }
    
    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(.alertTurquoise)
            .opacity(0.02)
            .blur(radius: 20)
            .clipped()
    }
    
    var content: some View {
        VStack {
            Spacer()
            loader
            
            if selectedTab == .fast {
                fastContent
            } else {
                title
            }
            
            Spacer()
        }
    }
    
    var title: some View {
        Text(getTitle())
            .font(.body14Montserrat)
            .foregroundColor(.neutral0)
            .bold()
            .multilineTextAlignment(.center)
    }
    
    var fastContent: some View {
        VStack {
            Text(NSLocalizedString("connectingWithServer...", comment: ""))
                .font(.body22BrockmannMedium)
            
            Text(NSLocalizedString("shouldOnlyTakeAMinute...", comment: ""))
                .font(.body14BrockmannMedium)
        }
        .foregroundColor(.lightText)
    }
    
    var loader: some View {
        animationVM?.view()
            .frame(width: 24, height: 24)
    }
    
    var pleaseWait: some View {
        Text(NSLocalizedString("pleaseWait", comment: ""))
            .font(.body14Montserrat)
            .foregroundColor(.neutral0)
            .bold()
            .multilineTextAlignment(.center)
            .padding(.top, 50)
    }
    
    private func getTitle() -> String {
        if let tssType, tssType == .Reshare {
            return NSLocalizedString("resharingLoaderTitle", comment: "")
        } else if let selectedTab {
            return selectedTab.loaderTitle
        } else {
            return NSLocalizedString("lookingForDevices", comment: "Looking for devices")
        }
    }
}

#Preview {
    ZStack {
        Background()
        LookingForDevicesLoader(tssType: .Reshare, selectedTab: .secure)
    }
}
