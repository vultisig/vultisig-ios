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
    /// Whether the passcode lock screen should be covering the app.
    @Published var isPasscodeLocked = false
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
    private let lockService: AppLockService
    /// Injected rather than called directly so a test can prove it runs *before*
    /// the launch gate reads the lock mode, which is the whole property.
    private let reconcileInstall: @MainActor () -> Void
    private var didTriggerAuthThisSession = false

    init(
        lockService: AppLockService = .shared,
        reconcileInstall: @escaping @MainActor () -> Void = { KeyshareInstallReconciler().reconcile() }
    ) {
        self.lockService = lockService
        self.reconcileInstall = reconcileInstall
    }

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

        if let vault = selectedVault {
            Task { await FastVaultEligibilityRefresher.shared.refreshIfStale(vault) }
        }
    }

    /// Triggers a fast-vault eligibility refresh for the currently selected vault
    /// if its cache is stale. Called by the app's scenePhase `.active` hook so
    /// the cache stays fresh after the app moves to the foreground.
    func refreshFastVaultEligibilityIfNeeded() {
        guard let vault = selectedVault else { return }
        Task { await FastVaultEligibilityRefresher.shared.refreshIfStale(vault) }
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
        didTriggerAuthThisSession = true

        #if DEBUG
        if CommandLine.arguments.contains("-skipAuthentication") {
            isAuthenticated = true
            isAuthenticationEnabled = true
            showSplashView = false
            didUserCancelAuthentication = false
            didAskForAuthentication = true
            return
        }
        #endif

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
        didTriggerAuthThisSession = false
        lockService.noteBackgrounded()
    }

    /// Engages the passcode lock if that is the configured mode.
    ///
    /// Forgetting the data key is what actually locks the app — the screen only
    /// reflects it. Without this the shares would stay readable behind the
    /// overlay and signing would still work.
    func lockWithPasscodeIfNeeded() {
        guard lockService.mode == .passcode else { return }
        PasscodeService.shared.lock()
        isPasscodeLocked = true
    }

    func markPasscodeUnlocked() {
        isPasscodeLocked = false
    }

    /// Restores the lock on launch when a passcode is configured, so a cold start
    /// is gated rather than only a return from the background.
    ///
    /// **Reconciliation runs first, synchronously, and that ordering is the
    /// point.** The lock mode lives in `UserDefaults` and the wrapped data key
    /// lives in the Keychain, and the two can disagree — `disablePasscode`
    /// changes the mode *before* deleting the wrapper precisely so an
    /// interruption leaves a repairable state rather than a gate with nothing
    /// behind it. `KeyshareInstallReconciler` is what repairs it, in both
    /// directions. It also runs at app `onAppear`, but nothing orders that
    /// against this, so the gate could be chosen from a mode reconciliation was
    /// about to change — after which the app sits open for the whole session
    /// with a wrapped key and no lock screen. Doing it here makes the ordering
    /// hold by construction instead of by luck; a second pass is a no-op,
    /// because the destructive half is marked once per container and the
    /// mode alignment only writes when it disagrees.
    @MainActor
    func restorePasscodeLockOnLaunch() {
        reconcileInstall()

        guard lockService.mode == .passcode else { return }
        PasscodeService.shared.lock()
        isPasscodeLocked = true
    }

    func enableAuth() {
        // The re-lock delay used to be five minutes hardcoded here, with no way
        // for anyone to change it. `AppLockService` owns that policy now.
        let shouldRelock = lockService.evaluateForeground()

        if shouldRelock, lockService.mode == .passcode {
            // The lock goes up BEFORE the cover comes down. Dropping the cover
            // first left the home screen — balances, addresses — visible for the
            // frames it took the lock screen to mount, on every single unlock.
            lockWithPasscodeIfNeeded()
            showCover = false
            return
        }

        showCover = false
        guard shouldRelock else { return }

        if !didTriggerAuthThisSession {
            resetLogin()
            continueLogin()
        }
    }

    func getBiometricType() {
        let authContext = LAContext()
         _ = authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)

        switch authContext.biometryType {
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
        if !showSplashView {
            showSplashView = true
        }
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
