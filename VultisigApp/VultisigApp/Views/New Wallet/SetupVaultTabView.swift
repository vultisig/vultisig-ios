//
//  SetupVaultTabView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-09.
//

import SwiftUI
import RiveRuntime

struct SetupVaultTabView: View {
    @Binding var selectedTab: SetupVaultState
    
    @State var showContent = false
    @State var showAnimation = false
    
    let animationVM = RiveViewModel(fileName: "ChooseVault")
    
    var body: some View {
        content
            .onAppear {
                setData()
            }
    }
    
    var content: some View {
        VStack {
            animation
            switchControl
            secureText
        }
        .padding(.horizontal, 16)
    }
    
    var animation: some View {
        SetupVaultAnimationManager(animationVM: animationVM, selectedTab: $selectedTab)
            .opacity(showAnimation ? 1 : 0)
            .blur(radius: showAnimation ? 0 : 10)
            .animation(.easeInOut, value: showAnimation)
    }
    
    var switchControl: some View {
        SetupVaultSwithControl(animationVM: animationVM, selectedTab: $selectedTab)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 50)
            .blur(radius: showContent ? 0 : 10)
            .scaleEffect(showContent ? 1 : 0.8)
            .animation(.spring, value: showContent)
    }
    
    var secureText: some View {
        SetupVaultSecureText(selectedTab: selectedTab)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 50)
            .blur(radius: showContent ? 0 : 10)
            .scaleEffect(showContent ? 1 : 0.8)
            .animation(.spring, value: showContent)
    }
    
    private func setData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showContent = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showAnimation = true
        }
    }
}

#Preview {
    ZStack {
        Background()
        SetupVaultTabView(selectedTab: .constant(.secure))
    }
}
