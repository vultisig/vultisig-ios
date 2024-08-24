//
//  AccountViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-24.
//

import SwiftUI
import LocalAuthentication

@MainActor
class AccountViewModel: ObservableObject {
    @AppStorage("showOnboarding") var showOnboarding: Bool = true
    @AppStorage("showCover") var showCover: Bool = true
    @AppStorage("isAuthenticationEnabled") var isAuthenticationEnabled: Bool = true
    @AppStorage("lastRecordedTime") var lastRecordedTime: String = ""
    
    @Published var isAuthenticated = false
    @Published var showSplashView = true
    @Published var didUserCancelAuthentication = false
    @Published var canLogin = true
    @Published var referenceID = UUID()
    
    func authenticateUser() {
        let context = LAContext()
        var error: NSError?

#if os(iOS)
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            authenticate(context)
        } else {
            isAuthenticationEnabled = false
            isAuthenticated = false
            showSplashView = false
            didUserCancelAuthentication = false
        }
#elseif os(macOS)
        isAuthenticationEnabled = false
        isAuthenticated = false
        showSplashView = false
        didUserCancelAuthentication = false
#endif
    }
    
    private func authenticate(_ context: LAContext) {
        if (context.biometryType == .faceID || context.biometryType == .touchID || context.biometryType == .opticID) && isRunningOnPhysicalDevice() {
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
        referenceID = UUID()
        guard !showOnboarding || isAuthenticationEnabled else {
            return
        }
        
        canLogin = false
        isAuthenticated = false
        didUserCancelAuthentication = false
        showSplashView = true
    }
    
    private func isRunningOnPhysicalDevice() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }
}
