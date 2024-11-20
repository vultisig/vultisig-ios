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
    @EnvironmentObject var vultExtensionViewModel: VultExtensionViewModel
    @EnvironmentObject var appViewModel: ApplicationState

    var body: some View {
        ZStack {
            NavigationStack {
                container
            }
            .accentColor(.white)
            .onOpenURL { incomingURL in
                handleDeeplink(incomingURL)
            }
            
            if accountViewModel.showCover {
                CoverView()
            }
        }
        .id(accountViewModel.referenceID)
        .colorScheme(.dark)
    }
    
    var content: some View {
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
    
    private func handleDeeplink(_ incomingURL: URL) {
        guard let deeplinkType = incomingURL.absoluteString.split(separator: ":").first else {
            return
        }
        
        if deeplinkType == "file" {
            vultExtensionViewModel.documentUrl = incomingURL
            vultExtensionViewModel.showImportView = true
        } else {
            deeplinkViewModel.extractParameters(incomingURL, vaults: vaults)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AccountViewModel())
        .environmentObject(DeeplinkViewModel())
        .environmentObject(ApplicationState())
}
