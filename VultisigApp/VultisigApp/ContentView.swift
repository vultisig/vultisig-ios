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
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var accountViewModel: AccountViewModel
    @EnvironmentObject var vultExtensionViewModel: VultExtensionViewModel
    
    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
        self._router = StateObject(wrappedValue: VultisigRouter(navigationRouter: navigationRouter))
    }

    var body: some View {
        ZStack {
            NavigationStack(path: $navigationRouter.navPath) {
                container
                    .navigationDestination(for: SendRoute.self) { router.sendRouter.build($0) }
            }
            .environment(\.router, router.navigationRouter)
            .accentColor(.white)
            .onOpenURL { incomingURL in
                #if DEBUG
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("📱 ContentView: onOpenURL chamado")
                print("   URL: \(incomingURL.absoluteString)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                #endif
                handleDeeplink(incomingURL)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                #if DEBUG
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("📱 ContentView: onContinueUserActivity chamado")
                #endif
                if let incomingURL = userActivity.webpageURL {
                    #if DEBUG
                    print("   URL: \(incomingURL.absoluteString)")
                    print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                    #endif
                    handleDeeplink(incomingURL)
                }
            }
            .onAppear {
                #if DEBUG
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("📱 ContentView: onAppear - App apareceu na tela")
                print("   vaults.count: \(vaults.count)")
                print("   showSplashView: \(accountViewModel.showSplashView)")
                print("   showCover: \(accountViewModel.showCover)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                #endif
            }
            
            if accountViewModel.showCover {
                CoverView()
            }
        }
        .id(accountViewModel.referenceID)
        .colorScheme(.dark)
        .sheetPresentedStyle()
        .background(Theme.colors.bgPrimary)
    }
    
    var content: some View {
        let _ = {
            #if DEBUG
            if accountViewModel.showSplashView {
                print("📱 ContentView.content: Mostrando splashView")
            } else if accountViewModel.showCover {
                print("📱 ContentView.content: Mostrando coverView")
            } else if vaults.count>0 {
                print("📱 ContentView.content: Mostrando homeView (vaults.count = \(vaults.count))")
            } else {
                print("📱 ContentView.content: Mostrando createVaultView (sem vaults)")
            }
            #endif
        }()
        
        return ZStack {
            if accountViewModel.showSplashView {
                splashView
            } else if accountViewModel.showCover {
                coverView
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
    
    var homeView: some View {
        HomeScreen()
            .onAppear {
                #if DEBUG
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                print("📱 ContentView: homeView apareceu")
                print("   deeplinkViewModel.type: \(String(describing: deeplinkViewModel.type))")
                print("   vaults.count: \(vaults.count)")
                print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                #endif
                
                // CRITICAL: Process pending deeplink when HomeScreen appears
                // This handles the case when app is closed and opened via QR code
                if deeplinkViewModel.type != nil {
                    #if DEBUG
                    print("   🔔 Deeplink pendente detectado no ContentView, HomeScreen vai processar")
                    #endif
                    // HomeScreen.onAppear will handle it, but we can also send notification here as backup
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        #if DEBUG
                        print("   📢 Enviando notificação ProcessDeeplink como backup")
                        #endif
                        NotificationCenter.default.post(name: NSNotification.Name("ProcessDeeplink"), object: nil)
                    }
                }
            }
    }
    
    var createVaultView: some View {
        CreateVaultView(selectedVault: nil, showBackButton: false)
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
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔍 ContentView.handleDeeplink chamado")
        print("   URL: \(incomingURL.absoluteString)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        #endif
        
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
        
        #if DEBUG
        print("   ✅ extractParameters chamado")
        print("   type agora é: \(String(describing: deeplinkViewModel.type))")
        print("   📢 Enviando notificação ProcessDeeplink IMEDIATAMENTE")
        #endif
        
        // Send notification immediately to process deeplink
        // onChange might not fire if HomeScreen is not in view hierarchy
        NotificationCenter.default.post(name: NSNotification.Name("ProcessDeeplink"), object: nil)
        
        // Also try with a small delay as fallback
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            #if DEBUG
            print("   🔄 Verificando type após 0.1s: \(String(describing: deeplinkViewModel.type))")
            #endif
            
            // If type is still set, send notification again
            if deeplinkViewModel.type != nil {
                #if DEBUG
                print("   ⚠️ Type ainda está setado, enviando notificação novamente")
                #endif
                NotificationCenter.default.post(name: NSNotification.Name("ProcessDeeplink"), object: nil)
            }
        }
    }
}

#Preview {
    ContentView(navigationRouter: .init())
        .environmentObject(AccountViewModel())
        .environmentObject(DeeplinkViewModel())
        .environmentObject(ApplicationState())
}
