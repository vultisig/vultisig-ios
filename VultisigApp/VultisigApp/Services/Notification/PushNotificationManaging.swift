//
//  PushNotificationManaging.swift
//  VultisigApp
//

import Foundation

@MainActor
protocol PushNotificationManaging: AnyObject {
    var isPermissionGranted: Bool { get set }
    var deviceToken: String? { get }
    var hasSeenNotificationPrompt: Bool { get set }
    var hadVaultsOnStartup: Bool { get set }

    func setupNotificationDelegate()
    func requestPermission() async -> Bool
    func checkPermissionStatus() async
    func setDeviceToken(_ token: Data)
    func isVaultOptedIn(_ vault: Vault) -> Bool
    func setVaultOptIn(_ vault: Vault, enabled: Bool)
    func hasPromptedVaultNotification(_ vault: Vault) -> Bool
    func markVaultNotificationPrompted(_ vault: Vault)
    func registerVault(pubKeyECDSA: String, localPartyID: String) async
    func reRegisterOptedInVaults(_ vaults: [Vault]) async
    func notifyVaultDevices(vault: Vault, qrCodeData: String) async
    func registerForRemoteNotifications()
}
