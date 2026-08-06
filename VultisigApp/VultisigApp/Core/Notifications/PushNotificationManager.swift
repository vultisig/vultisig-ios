//
//  PushNotificationManager.swift
//  VultisigApp
//

import CryptoKit
import Foundation
import UserNotifications
import SwiftUI
import SwiftData
import OSLog

@MainActor
class PushNotificationManager: ObservableObject {
    static let shared = PushNotificationManager()

    @Published var isPermissionGranted: Bool = false
    @Published var deviceToken: String?
    @Published var foregroundNotification: ForegroundNotificationData?

    var hadVaultsOnStartup = false

    @AppStorage("hasSeenNotificationPrompt") var hasSeenNotificationPrompt: Bool = false
    @AppStorage("notificationsEnabled") var isNotificationsEnabled: Bool = false

    private let keychainService: KeychainService
    private let notificationService: NotificationServicing
    private let fetchVaults: () throws -> [Vault]
    private let canPresentForegroundBanner: @MainActor () -> Bool
    private let logger = Log.app.other

    private let notificationDelegate = NotificationDelegate()

    init(
        notificationService: NotificationServicing = NotificationService(),
        keychainService: KeychainService = DefaultKeychainService.shared,
        fetchVaults: (() throws -> [Vault])? = nil,
        canPresentForegroundBanner: (@MainActor () -> Bool)? = nil
    ) {
        self.notificationService = notificationService
        self.keychainService = keychainService
        self.fetchVaults = fetchVaults ?? {
            try Storage.shared.modelContext.fetch(FetchDescriptor<Vault>())
        }
        self.canPresentForegroundBanner = canPresentForegroundBanner ?? {
            ForegroundNotificationPresentationPolicy.canPresentCustomBanner
        }
    }

    // MARK: - Notification Delegate

    func setupNotificationDelegate() {
        notificationDelegate.onForegroundNotification = { [weak self] content, completion in
            Task { @MainActor in
                guard let self else {
                    completion(false)
                    return
                }
                completion(self.handleForegroundNotification(content))
            }
        }
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

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    func checkPermissionStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isPermissionGranted = settings.authorizationStatus == .authorized
    }

    // MARK: - Device Token

    func setDeviceToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        // An unreadable Keychain counts as "no previous token", which re-registers
        // every opted-in vault. Re-registering an unchanged token is harmless;
        // skipping a registration for a token that really did change is not.
        let previousToken = keychainService.getDeviceToken().valueTreatingUnavailableAsAbsent
        deviceToken = tokenString
        keychainService.setDeviceToken(tokenString)

        guard tokenString != previousToken else {
            logger.info("Device token unchanged, skipping re-registration")
            return
        }

        logger.info("Device token changed, re-registering vaults")
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

        do {
            try Storage.shared.save()
        } catch {
            logger.error("Failed to save vault opt-in: \(error.localizedDescription)")
            return
        }

        let vaultId = notificationVaultId(for: vault)
        let localPartyID = vault.localPartyID

        Task {
            if enabled {
                await registerVault(
                    vaultId: vaultId,
                    localPartyID: localPartyID
                )
            } else {
                await unregisterVault(
                    vaultId: vaultId,
                    localPartyID: localPartyID
                )
            }
        }
    }

    func setAllVaultsOptIn(_ vaults: [Vault], enabled: Bool) {
        for vault in vaults {
            let settings = getOrCreateSettings(for: vault)
            settings.notificationsEnabled = enabled
        }

        do {
            try Storage.shared.save()
        } catch {
            logger.error("Failed to save all vaults opt-in: \(error.localizedDescription)")
            return
        }

        let vaultIdentifiers = vaults.map {
            (notificationVaultId(for: $0), $0.localPartyID)
        }

        Task {
            for (vaultId, localPartyID) in vaultIdentifiers {
                if enabled {
                    await registerVault(
                        vaultId: vaultId,
                        localPartyID: localPartyID
                    )
                } else {
                    await unregisterVault(
                        vaultId: vaultId,
                        localPartyID: localPartyID
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

        do {
            try Storage.shared.save()
        } catch {
            logger.error("Failed to save vault notification prompt: \(error.localizedDescription)")
        }
    }

    // MARK: - Registration

    func registerVault(vaultId: String, localPartyID: String) async {
        guard let token = deviceToken else {
            logger.warning("No device token available for vault registration")
            return
        }

        let request = DeviceRegistrationRequest(
            vaultId: vaultId,
            partyName: localPartyID,
            token: token,
            deviceType: "apple"
        )

        do {
            try await notificationService.registerDevice(request: request)
            logger.info("Vault registered for notifications")
        } catch {
            logger.error("Failed to register vault: \(error.localizedDescription)")
        }
    }

    func unregisterVault(vaultId: String, localPartyID: String) async {
        do {
            try await notificationService.unregisterDevice(
                vaultId: vaultId,
                partyName: localPartyID
            )
            logger.info("Vault unregistered from notifications")
        } catch {
            logger.error("Failed to unregister vault: \(error.localizedDescription)")
        }
    }

    func reRegisterOptedInVaults(_ vaults: [Vault]) async {
        let optedInIdentifiers = vaults
            .filter { isVaultOptedIn($0) }
            .map {
                (notificationVaultId(for: $0), $0.localPartyID)
            }

        for (vaultId, localPartyID) in optedInIdentifiers {
            await registerVault(
                vaultId: vaultId,
                localPartyID: localPartyID
            )
        }
    }

    // MARK: - Notify

    func notifyVaultDevices(vault: Vault, qrCodeData: String) async {
        let request = NotifyRequest(
            vaultId: notificationVaultId(for: vault),
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

    func unregisterForRemoteNotifications() {
        #if os(iOS)
        UIApplication.shared.unregisterForRemoteNotifications()
        #elseif os(macOS)
        NSApplication.shared.unregisterForRemoteNotifications()
        #endif
    }

    // MARK: - Private

    private func notificationVaultId(for vault: Vault) -> String {
        let data = Data((vault.pubKeyECDSA + vault.hexChainCode).utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @discardableResult
    func handleForegroundNotification(_ content: UNNotificationContent) -> Bool {
        guard canPresentForegroundBanner() else {
            logger.info("Custom foreground banner unavailable while a modal is presented")
            return false
        }

        let vaults: [Vault]
        do {
            vaults = try fetchVaults()
        } catch {
            logger.error("Failed to fetch vaults for foreground notification: \(error.localizedDescription)")
            return false
        }

        guard let parsedNotification = ForegroundNotificationParser.parse(
            content: content,
            vaults: vaults
        ) else {
            logger.warning("Unable to parse foreground notification; using system presentation")
            return false
        }

        foregroundNotification = parsedNotification
        return true
    }

    private func reRegisterOptedInVaults() async {
        guard deviceToken != nil else { return }

        let descriptor = FetchDescriptor<VaultSettings>(
            predicate: #Predicate<VaultSettings> { $0.notificationsEnabled == true }
        )
        guard let results = try? Storage.shared.modelContext.fetch(descriptor) else { return }

        let identifiers = results.compactMap { settings -> (String, String)? in
            guard let vault = settings.vault else { return nil }
            return (notificationVaultId(for: vault), vault.localPartyID)
        }

        for (vaultId, localPartyID) in identifiers {
            await registerVault(
                vaultId: vaultId,
                localPartyID: localPartyID
            )
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    var onForegroundNotification: ((
        UNNotificationContent,
        @escaping (Bool) -> Void
    ) -> Void)?

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        presentationOptions(
            for: notification.request.content,
            completion: completionHandler
        )
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

    func presentationOptions(
        for content: UNNotificationContent,
        completion: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard let onForegroundNotification else {
            completion(ForegroundNotificationPresentationPolicy.systemOptions)
            return
        }

        onForegroundNotification(content) { handled in
            completion(
                handled
                    ? ForegroundNotificationPresentationPolicy.customOptions
                    : ForegroundNotificationPresentationPolicy.systemOptions
            )
        }
    }
}

enum ForegroundNotificationPresentationPolicy {
    static let customOptions: UNNotificationPresentationOptions = [.sound]
    static let systemOptions: UNNotificationPresentationOptions = [.banner, .list, .sound]

    @MainActor
    static var canPresentCustomBanner: Bool {
        #if os(iOS)
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let keyWindow = windowScene.windows.first(where: \.isKeyWindow),
              let rootViewController = keyWindow.rootViewController else {
            return false
        }
        return rootViewController.presentedViewController == nil
        #elseif os(macOS)
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow else {
            return false
        }
        return window.attachedSheet == nil
        #endif
    }
}
