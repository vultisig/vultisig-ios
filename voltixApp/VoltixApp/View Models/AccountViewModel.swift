//
//  AccountViewModel.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-24.
//

import SwiftUI
import LocalAuthentication

@MainActor
class AccountViewModel: ObservableObject {
    @AppStorage("showOnboarding") var showOnboarding: Bool = true
    @AppStorage("isAuthenticationEnabled") var isAuthenticationEnabled: Bool = true
    
    @Published var isAuthenticated: Bool = false
    @Published var showSplashView = true
    
    func authenticateUser() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            
            if context.biometryType == .faceID {
                context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Authenticate to check Face ID") { success, error in
                    DispatchQueue.main.async {
                        if success {
                            self.isAuthenticated = true
                            self.showSplashView = false
                            self.isAuthenticationEnabled = true
                        } else {
                            if let error = error as? LAError {
                                switch error.code {
                                case .biometryLockout, .biometryNotEnrolled, .biometryNotAvailable:
                                    self.isAuthenticationEnabled = false
                                default:
                                    self.isAuthenticationEnabled = true
                                }
                            }
                            self.isAuthenticated = false
                            self.showSplashView = true
                        }
                    }
                }
            } else {
                isAuthenticationEnabled = false
                isAuthenticated = false
                showSplashView = false
            }
        } else {
            isAuthenticationEnabled = false
            isAuthenticated = false
            showSplashView = false
        }
    }
}
