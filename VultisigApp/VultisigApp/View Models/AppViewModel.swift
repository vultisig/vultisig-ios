//
//  AppViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-24.
//

import SwiftUI
import LocalAuthentication

class AppViewModel: ObservableObject {
    @AppStorage("showOnboarding") var showOnboarding: Bool = true
    @AppStorage("showCover") var showCover: Bool = true
    @AppStorage("isAuthenticationEnabled") var isAuthenticationEnabled: Bool = true
    @AppStorage("didAskForAuthentication") var didAskForAuthentication: Bool = false
    @AppStorage("lastRecordedTime") var lastRecordedTime: String = ""
    @AppStorage("vaultName") var vaultName: String = ""
    @AppStorage("selectedPubKeyECDSA") var selectedPubKeyECDSA: String = ""

    @Published var isAuthenticated = false
    @Published var showSplashView = true
    @Published var didUserCancelAuthentication = false
    @Published var canLogin = true
    @Published var authenticationType: AuthenticationType = .None
    
    // Properties to manage global navigation
    @Published private(set) var selectedVault: Vault?
    @Published private(set) var showingVaultSelector: Bool = false
    @Published var restartNavigation: Bool = false
    @Published var showCamera: Bool = false
    
    private let logic = AccountLogic()
    
    static let shared = AppViewModel()
    
    func restart() {
        set(selectedVault: selectedVault, restartNavigation: true)
    }
    
    func set(selectedVault: Vault?, showingVaultSelector: Bool = false, restartNavigation: Bool = true) {
        self.selectedVault = selectedVault
        self.vaultName = selectedVault?.name ?? ""
        self.selectedPubKeyECDSA = selectedVault?.pubKeyECDSA ?? ""
        
        self.showingVaultSelector = showingVaultSelector
        self.restartNavigation = restartNavigation
    }
    
    func loadSelectedVault(for vaults: [Vault]) {
        if vaultName.isEmpty || selectedPubKeyECDSA.isEmpty {
            // when vaultName is empty / selectedPubKeyECDSA is empty, select the first vault if available
            // otherwise the app have nothing to show
            set(selectedVault: vaults.first, showingVaultSelector: true)
            return
        }

        for vault in vaults {
            if vaultName == vault.name && selectedPubKeyECDSA == vault.pubKeyECDSA {
                set(selectedVault: vault)
                return
            }
        }

        set(selectedVault: nil, showingVaultSelector: true)
    }
    
    func authenticateUser() {
        let context = LAContext()
        var error: NSError?
        
        getBiometricType()

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            authenticate(context)
        } else {
            isAuthenticationEnabled = false
            isAuthenticated = false
            showSplashView = false
            didUserCancelAuthentication = false
            didAskForAuthentication = true
        }
    }
    
    func authenticateUserIfNeeded() {
        guard !didAskForAuthentication else { return }
        authenticateUser()
    }
    
    private func authenticate(_ context: LAContext) {
        self.didAskForAuthentication = true
        if (context.biometryType == .faceID || context.biometryType == .touchID || context.biometryType == .opticID) && logic.isRunningOnPhysicalDevice() {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Authenticate to check Face ID") { success, error in
                DispatchQueue.main.async {
                    if success {
                        self.isAuthenticated = true
                        self.showSplashView = false
                        self.isAuthenticationEnabled = true
                        self.didUserCancelAuthentication = false
                    } else {
                        if let error = error as? LAError {
                            switch error.code {
                            case .biometryLockout, .biometryNotEnrolled, .biometryNotAvailable:
                                self.isAuthenticationEnabled = false
                                self.showSplashView = false
                            default:
                                self.isAuthenticationEnabled = true
                                self.showSplashView = true
                            }
                        }
                        self.isAuthenticated = false
                        self.didUserCancelAuthentication = true
                    }
                }
            }
        } else {
            isAuthenticationEnabled = false
            isAuthenticated = false
            showSplashView = false
            didUserCancelAuthentication = false
        }
    }
    
    func revokeAuth() {
        showCover = true
        let formatter = ISO8601DateFormatter()
        lastRecordedTime = formatter.string(from: Date())
    }
    
    func enableAuth() {
        showCover = false
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: lastRecordedTime) ?? Date()
        let interval = Date().timeIntervalSince(date)
        lastRecordedTime = formatter.string(from: Date())
        
        if interval>60*5 {
            resetLogin()
            continueLogin()
        }
    }
    
    func getBiometricType() {
        let authContext = LAContext()
        let _ = authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        
        switch(authContext.biometryType) {
        case .none:
            authenticationType = .None
        case .touchID:
            authenticationType = .TouchID
        case .faceID:
            authenticationType = .FaceID
        case .opticID:
            authenticationType = .OpticID
        @unknown default:
            authenticationType = .None
        }
    }
    
    private func continueLogin() {
        guard !isAuthenticated else {
            return
        }
        
        guard !showOnboarding || isAuthenticationEnabled else {
            return
        }
        
        canLogin = true
        showSplashView = false
        showSplashView = true
    }
    
    private func resetLogin() {
        guard !showOnboarding || isAuthenticationEnabled else {
            return
        }
        
        canLogin = false
        isAuthenticated = false
        didUserCancelAuthentication = false
        showSplashView = true
    }
}

// MARK: - AccountLogic

struct AccountLogic {
    func isRunningOnPhysicalDevice() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #elseif DEBUG
        return false
        #else
        return true
        #endif
    }
}
