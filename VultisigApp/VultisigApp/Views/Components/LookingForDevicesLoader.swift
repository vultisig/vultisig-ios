//
//  LookingForDevicesLoader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-20.
//

import SwiftUI

struct LookingForDevicesLoader: View {
    var selectedTab: SetupVaultState? = nil
    @State var didSwitch = false
    
    var body: some View {
        VStack {
            title
            loader
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cornerRadius(10)
        .shadow(radius: 5)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                didSwitch.toggle()
            }
        }
    }
    
    var title: some View {
        ZStack {
            if let selectedTab {
                Text(selectedTab.loaderTitle)
            } else {
                Text(NSLocalizedString("lookingForDevices", comment: "Looking for devices"))
            }
        }
        .font(.body14Montserrat)
        .foregroundColor(.neutral0)
        .bold()
        .multilineTextAlignment(.center)
    }
    
    var loader: some View {
        HStack {
            Circle()
                .frame(width: 20, height: 20)
                .foregroundColor(.loadingBlue)
                .offset(x: didSwitch ? 0 : 28)
            
            Circle()
                .frame(width: 20, height: 20)
                .foregroundColor(.loadingGreen)
                .offset(x: didSwitch ? 0 : -28)
        }
        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: didSwitch)
        .frame(height: 20)
    }
}

#Preview {
    ZStack {
        Background()
        LookingForDevicesLoader(selectedTab: .fast)
    }
}
