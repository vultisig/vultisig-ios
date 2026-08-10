//
//  AppLockPanelHost.swift
//  VultisigApp
//

#if os(macOS)
import SwiftUI

/// The Mac's half of ``AppLockHost``.
@MainActor
final class AppLockPanelHost: ObservableObject {

    static let shared = AppLockPanelHost()

    /// `false`, so the root overlay goes on carrying the lock screen itself on
    /// the Mac. An overlay covers everything `CrossPlatformSheet` draws in the
    /// view hierarchy, which on macOS below 26 is every sheet the app has; what
    /// it does not cover is a window-attached sheet, which is what macOS 26 and
    /// every `.alert` use.
    @Published private(set) var hostsLockScreen = false

    func update(
        to _: AppLockPresentation,
        onUnlocked _: @escaping () -> Void,
        onAttemptFailed _: @escaping () -> Void
    ) {}
}
#endif
