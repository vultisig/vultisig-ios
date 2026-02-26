//
//  PushNotificationManager.swift
//  VultisigApp
//

import Foundation
import UserNotifications
import SwiftUI
import SwiftData
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

    // MARK: - Vault Settings

    private func getOrCreateSettings(for vault: Vault) -> VaultSettings {
        if let settings = vault.settings { return settings }
        let settings = VaultSettings(vault: vault)
        Storage.shared.insert(settings)
        vault.settings = settings
        return settings
    }

    // MARK: - Vault Opt-In

    func isVaultOptedIn(_ vault: Vault) -> Bool {
        vault.settings?.notificationsEnabled ?? false
    }

    func setVaultOptIn(_ vault: Vault, enabled: Bool) {
        let settings = getOrCreateSettings(for: vault)
        settings.notificationsEnabled = enabled
        try? Storage.shared.save()

        Task {
            if enabled {
                await registerVault(
                    pubKeyECDSA: vault.pubKeyECDSA,
                    localPartyID: vault.localPartyID
                )
            } else {
                await unregisterVault(
                    pubKeyECDSA: vault.pubKeyECDSA,
                    localPartyID: vault.localPartyID
                )
            }
        }
    }

    func setAllVaultsOptIn(_ vaults: [Vault], enabled: Bool) {
        for vault in vaults {
            let settings = getOrCreateSettings(for: vault)
            settings.notificationsEnabled = enabled
        }
        try? Storage.shared.save()

        Task {
            for vault in vaults {
                if enabled {
                    await registerVault(
                        pubKeyECDSA: vault.pubKeyECDSA,
                        localPartyID: vault.localPartyID
                    )
                } else {
                    await unregisterVault(
                        pubKeyECDSA: vault.pubKeyECDSA,
                        localPartyID: vault.localPartyID
                    )
                }
            }
        }
    }

    // MARK: - Vault Notification Prompt

    func hasPromptedVaultNotification(_ vault: Vault) -> Bool {
        vault.settings?.notificationsPrompted ?? false
    }

    func markVaultNotificationPrompted(_ vault: Vault) {
        let settings = getOrCreateSettings(for: vault)
        settings.notificationsPrompted = true
        try? Storage.shared.save()
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

    func unregisterVault(pubKeyECDSA: String, localPartyID: String) async {
        do {
            try await notificationService.unregisterDevice(
                vaultId: pubKeyECDSA,
                partyName: localPartyID
            )
            logger.info("Vault unregistered from notifications")
        } catch {
            logger.error("Failed to unregister vault: \(error.localizedDescription)")
        }
    }

    func reRegisterOptedInVaults(_ vaults: [Vault]) async {
        for vault in vaults where isVaultOptedIn(vault) {
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

        let descriptor = FetchDescriptor<VaultSettings>(
            predicate: #Predicate<VaultSettings> { $0.notificationsEnabled == true }
        )
        guard let results = try? Storage.shared.modelContext.fetch(descriptor) else { return }

        for settings in results {
            guard let vault = settings.vault else { continue }
            await registerVault(
                pubKeyECDSA: vault.pubKeyECDSA,
                localPartyID: vault.localPartyID
            )
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
        let deeplink = response.notification.request.content.userInfo["deeplink"] as? String
        if let deeplink, let url = URL(string: deeplink) {
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
