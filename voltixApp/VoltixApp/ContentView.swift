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
    
    @EnvironmentObject var accountViewModel: AccountViewModel
    
    var body: some View {
        NavigationStack {
            ZStack {
                if accountViewModel.showSplashView {
                    splashView
                } else if accountViewModel.showOnboarding {
                    onboardingView
                } else if vaults.count>0 {
                    homeView
                } else {
                    createVaultView
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarTitleTextColor(.neutral0)
        }
    }
    
    var splashView: some View {
        WelcomeView()
            .onAppear {
                authenticateUser()
            }
    }
    
    var onboardingView: some View {
        OnboardingView()
    }
    
    var homeView: some View {
        HomeView()
    }
    
    var createVaultView: some View {
        CreateVaultView()
    }
    
    private func authenticateUser() {
        guard !accountViewModel.showOnboarding && vaults.count>0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                accountViewModel.showSplashView = false
            }
            return
        }
        
        accountViewModel.authenticateUser()
    }
}

#Preview {
    ContentView()
        .environmentObject(AccountViewModel())
}
