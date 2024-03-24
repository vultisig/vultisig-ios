//
//  ContentView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-24.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query var vaults: [Vault]
    @State var showSplashView = true
    @EnvironmentObject var accountViewModel: AccountViewModel
    
    var body: some View {
        ZStack {
            if showSplashView {
                WelcomeView()
            } else if accountViewModel.showOnboarding {
                OnboardingView()
            } else if vaults.count>0 {
                HomeView()
            } else {
                CreateVaultView()
            }
        }
        .onAppear {
            performSegue()
        }
    }
    
    var onboarding: some View {
        OnboardingView()
    }
    
    var splash: some View {
        WelcomeView()
    }
    
    private func performSegue() {
        // Perform pre app load logics here
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showSplashView = false
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AccountViewModel())
}
