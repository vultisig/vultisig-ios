//
//  ContentView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-24.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Query var vaults: [Vault]
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var accountViewModel: AccountViewModel
    @EnvironmentObject var appViewModel: ApplicationState
    
    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    if accountViewModel.showSplashView {
                        splashView
                    } else if accountViewModel.showCover {
                        coverView
                    } else if accountViewModel.showOnboarding {
                        onboardingView
                    } else if vaults.count>0 {
                        homeView
                    } else {
                        createVaultView
                    }
                }
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarTitleTextColor(.neutral0)
#endif
            }
            .onOpenURL { incomingURL in
                deeplinkViewModel.extractParameters(incomingURL, vaults: vaults)
            }
            
            if accountViewModel.showCover {
                CoverView()
            }
        }
        .id(accountViewModel.referenceID)
        .colorScheme(.dark)
    }
    
    var splashView: some View {
        WelcomeView()
            .onAppear {
                setData()
            }
            .onChange(of: accountViewModel.canLogin) { oldValue, newValue in
                if newValue {
                    authenticateUser()
                }
            }
    }
    
    var coverView: some View {
        CoverView()
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
    
    private func setData() {
        authenticateUser()
        appViewModel.checkCameraPermission()
    }
    
    private func authenticateUser() {
        guard accountViewModel.canLogin else {
            return
        }
        
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
        .environmentObject(DeeplinkViewModel())
        .environmentObject(ApplicationState())
}
