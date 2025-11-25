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
    
    @ObservedObject var navigationRouter: NavigationRouter
    @StateObject var router: VultisigRouter
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var vultExtensionViewModel: VultExtensionViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    
    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
        self._router = StateObject(wrappedValue: VultisigRouter(navigationRouter: navigationRouter))
    }

    var body: some View {
        NavigationStack(path: $navigationRouter.navPath) {
            container
                .navigationDestination(for: SendRoute.self) { router.sendRouter.build($0) }
        }
        .environment(\.router, router.navigationRouter)
        .id(appViewModel.referenceID)
        .colorScheme(.dark)
        .accentColor(.white)
        .sheetPresentedStyle()
        .background(Theme.colors.bgPrimary)
        .onOpenURL { incomingURL in
            handleDeeplink(incomingURL)
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
            if let incomingURL = userActivity.webpageURL {
                handleDeeplink(incomingURL)
            }
        }
        .onLoad {
            appViewModel.set(selectedVault: vaults.first)
        }
    }
    
    var content: some View {
        Group {
            if appViewModel.showSplashView {
                splashView
            } else if appViewModel.showCover {
                CoverView()
            } else if vaults.count == 0 {
                CreateVaultView(selectedVault: nil, showBackButton: false)
            } else if let selectedVault = appViewModel.selectedVault {
                HomeScreen(
                    initialVault: selectedVault,
                    showingVaultSelector: appViewModel.showingVaultSelector
                )
            }
        }
        .transition(.opacity)
        .animation(.interpolatingSpring, value: appViewModel.referenceID)
    }
    
    var splashView: some View {
        WelcomeView()
            .onAppear {
                setData()
            }
            .onChange(of: appViewModel.canLogin) { oldValue, newValue in
                if newValue {
                    authenticateUser()
                }
            }
    }
    
    private func setData() {
        authenticateUser()
    }
    
    private func authenticateUser() {
        guard appViewModel.canLogin else {
            return
        }
        
        guard !appViewModel.showOnboarding && vaults.count>0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                appViewModel.showSplashView = false
            }
            return
        }
        
        appViewModel.authenticateUser()
    }
    
    private func handleDeeplink(_ incomingURL: URL) {
        guard let deeplinkType = incomingURL.absoluteString.split(separator: ":").first else {
            return
        }
        
        if deeplinkType == "file" {
            vultExtensionViewModel.documentUrl = incomingURL
            vultExtensionViewModel.showImportView = true
        } else if deeplinkType == "https" {
            let updatedURL = incomingURL.absoluteString.replacingOccurrences(of: "https", with: "vultisig")
            
            guard let url = URL(string: updatedURL) else {
                return
            }
            
            deeplinkViewModel.extractParameters(url, vaults: vaults)
        } else {
            deeplinkViewModel.extractParameters(incomingURL, vaults: vaults)
        }
        
        NotificationCenter.default.post(name: NSNotification.Name("ProcessDeeplink"), object: nil)
        
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            if deeplinkViewModel.type != nil {
                NotificationCenter.default.post(name: NSNotification.Name("ProcessDeeplink"), object: nil)
            }
        }
    }
}

#Preview {
    ContentView(navigationRouter: .init())
        .environmentObject(AppViewModel())
        .environmentObject(ApplicationState())
        .environmentObject(HomeViewModel())
        .environmentObject(CoinSelectionViewModel())
        .environmentObject(DeeplinkViewModel())
}
