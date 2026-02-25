//
//  MockPushNotificationManager.swift
//  VultisigApp
//

#if DEBUG
import Foundation

@MainActor
final class MockPushNotificationManager: PushNotificationManager {
    convenience init(
        permissionGranted: Bool,
        hadVaults: Bool = true
    ) {
        self.init()
        self.isPermissionGranted = permissionGranted
        self.hadVaultsOnStartup = hadVaults
    }
}
#endif
