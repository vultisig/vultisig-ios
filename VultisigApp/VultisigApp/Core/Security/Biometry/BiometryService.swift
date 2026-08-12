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

    /// Held so the privacy cover can tell a prompt this raised from the app
    /// actually leaving — see ``AppLockService/isPresentingSystemAuthPrompt``.
    private let lockService: AppLockService
    /// Injected so a test can reach the one branch that matters here.
    ///
    /// The prompting path is unreachable in a simulator by construction —
    /// ``isRunningOnPhysicalDevice()`` is false there and the call short-circuits
    /// to success — so without a seam the bracketing around the prompt, which is
    /// the whole point of this type knowing about the lock service at all, is
    /// exactly the part no test can run.
    private let makeContext: () -> LAContext
    private let isPhysicalDevice: () -> Bool

    init(
        lockService: AppLockService = .shared,
        makeContext: @escaping () -> LAContext = { LAContext() },
        isPhysicalDevice: @escaping () -> Bool = { BiometryService.runningOnPhysicalDevice }
    ) {
        self.lockService = lockService
        self.makeContext = makeContext
        self.isPhysicalDevice = isPhysicalDevice
    }

    func authenticate(
        reason: String,
        onSuccess: @escaping () -> Void,
        onError: ((Error) -> Void)?
    ) {
        let context = makeContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            if isPhysicalDevice() {
                switch context.biometryType {
                case .touchID, .faceID, .opticID:
                    // Bracketed around the prompt, and only around the branch
                    // that actually raises one — the app is about to be made
                    // inactive by its own sheet, and the privacy cover must not
                    // read that as the app leaving. See
                    // ``AppLockService/isPresentingSystemAuthPrompt``.
                    //
                    // Before `evaluatePolicy` rather than after: the `.inactive`
                    // can arrive before that call returns.
                    let ticket = lockService.beginSystemAuthPrompt()
                    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                        DispatchQueue.main.async {
                            // First, and outside the branches below: a cancelled
                            // prompt is as gone as a successful one, and either
                            // way the app is about to be told it is active again.
                            lockService.endSystemAuthPrompt(ticket)
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
}

extension BiometryService {

    static var runningOnPhysicalDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }
}
