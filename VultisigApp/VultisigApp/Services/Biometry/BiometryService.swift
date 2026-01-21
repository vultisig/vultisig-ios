//
//  BiometryService.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 14.10.2024.
//

import Foundation
import LocalAuthentication

struct BiometryService {

    static let shared = BiometryService()

    func authenticate(
        reason: String,
        onSuccess: @escaping () -> Void,
        onError: ((Error) -> Void)?
    ) {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            if isRunningOnPhysicalDevice() {
                switch context.biometryType {
                case .touchID, .faceID, .opticID:
                    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                        DispatchQueue.main.async {
                            if let error, !success {
                                onError?(error)
                            } else if success {
                                onSuccess()
                            }
                        }
                    }
                default:
                    onError?(Errors.wrongBiometryType)
                }
            } else {
                onSuccess()
            }
        } else {
            onError?(Errors.cantEvaluatePolicy)
        }
    }
}

private extension BiometryService {

    enum Errors: Error {
        case cantEvaluatePolicy
        case wrongBiometryType
    }

    func isRunningOnPhysicalDevice() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }
}
