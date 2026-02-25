//
//  PushNotificationManager.swift
//  VultisigApp
//

import Foundation
import UserNotifications
import SwiftUI
import OSLog

@MainActor
class PushNotificationManager: ObservableObject, PushNotificationManaging {
    static let shared = PushNotificationManager()

    @Published var isPermissionGranted: Bool = false
    @Published var deviceToken: String?

    var hadVaultsOnStartup = false

    @AppStorage("hasSeenNotificationPrompt") var hasSeenNotificationPrompt: Bool = false

    private let notificationService = NotificationService()
    private let logger = Logger(
        subsystem: "com.vultisig.wallet",
        category: "PushNotifications"
    )

    private let vaultOptInKey = "vaultNotificationOptIn"
    private let vaultNotificationPromptedKey = "vaultNotificationPrompted"

    private let notificationDelegate = NotificationDelegate()

    init() {}

    // MARK: - Notification Delegate

    func setupNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            isPermissionGranted = granted
            if granted {
                registerForRemoteNotifications()
            }
            return granted
        } catch {
            logger.error("Failed to request notification permission: \(error.localizedDescription)")
            return false
        }
    }

    func checkPermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isPermissionGranted = settings.authorizationStatus == .authorized
    }

    // MARK: - Device Token

    func setDeviceToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        deviceToken = tokenString
        logger.info("Device token received")

        Task {
            await reRegisterOptedInVaults()
        }
    }

    // MARK: - Vault Opt-In

    func isVaultOptedIn(pubKeyECDSA: String) -> Bool {
        let optInDict = UserDefaults.standard.dictionary(forKey: vaultOptInKey) as? [String: Bool] ?? [:]
        return optInDict[pubKeyECDSA] ?? false
    }

    func setVaultOptIn(vault: Vault, enabled: Bool) {
        var optInDict = UserDefaults.standard.dictionary(forKey: vaultOptInKey) as? [String: Bool] ?? [:]
        optInDict[vault.pubKeyECDSA] = enabled
        UserDefaults.standard.set(optInDict, forKey: vaultOptInKey)

        if enabled {
            Task {
                await registerVault(
                    pubKeyECDSA: vault.pubKeyECDSA,
                    localPartyID: vault.localPartyID
                )
            }
        }
    }

    // MARK: - Vault Notification Prompt

    func hasPromptedVaultNotification(pubKeyECDSA: String) -> Bool {
        let dict = UserDefaults.standard.dictionary(forKey: vaultNotificationPromptedKey) as? [String: Bool] ?? [:]
        return dict[pubKeyECDSA] ?? false
    }

    func markVaultNotificationPrompted(pubKeyECDSA: String) {
        var dict = UserDefaults.standard.dictionary(forKey: vaultNotificationPromptedKey) as? [String: Bool] ?? [:]
        dict[pubKeyECDSA] = true
        UserDefaults.standard.set(dict, forKey: vaultNotificationPromptedKey)
    }

    // MARK: - Registration

    func registerVault(pubKeyECDSA: String, localPartyID: String) async {
        guard let token = deviceToken else {
            logger.warning("No device token available for vault registration")
            return
        }

        let deviceType = "apple"

        let request = DeviceRegistrationRequest(
            vaultId: pubKeyECDSA,
            partyName: localPartyID,
            token: token,
            deviceType: deviceType
        )

        do {
            try await notificationService.registerDevice(request: request)
            logger.info("Vault registered for notifications")
        } catch {
            logger.error("Failed to register vault: \(error.localizedDescription)")
        }
    }

    func reRegisterOptedInVaults(_ vaults: [Vault]) async {
        for vault in vaults where isVaultOptedIn(pubKeyECDSA: vault.pubKeyECDSA) {
            await registerVault(
                pubKeyECDSA: vault.pubKeyECDSA,
                localPartyID: vault.localPartyID
            )
        }
    }

    // MARK: - Notify

    func notifyVaultDevices(vault: Vault, qrCodeData: String) async {
        let request = NotifyRequest(
            vaultId: vault.pubKeyECDSA,
            vaultName: vault.name,
            localPartyId: vault.localPartyID,
            qrCodeData: qrCodeData
        )

        do {
            try await notificationService.sendNotification(request: request)
            logger.info("Notification sent to vault devices")
        } catch {
            logger.error("Failed to notify vault devices: \(error.localizedDescription)")
        }
    }

    // MARK: - Platform Registration

    func registerForRemoteNotifications() {
        #if os(iOS)
        UIApplication.shared.registerForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #endif
    }

    // MARK: - Private

    private func reRegisterOptedInVaults() async {
        guard deviceToken != nil else { return }

        let optInDict = UserDefaults.standard.dictionary(forKey: vaultOptInKey) as? [String: Bool] ?? [:]
        for (pubKeyECDSA, isOptedIn) in optInDict where isOptedIn {
            await registerVault(pubKeyECDSA: pubKeyECDSA, localPartyID: "")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

private class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let body = response.notification.request.content.body
        if let url = URL(string: body), url.scheme == "vultisig" {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("HandlePushNotification"),
                    object: url
                )
            }
        }
        completionHandler()
    }
}
