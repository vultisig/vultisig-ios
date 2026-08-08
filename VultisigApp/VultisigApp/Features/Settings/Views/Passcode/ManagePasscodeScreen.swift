//
//  ManagePasscodeScreen.swift
//  VultisigApp
//

import SwiftUI

/// Settings entry point for the passcode: turn it on, change it, turn it off,
/// and reach the auto-lock interval once it is on.
struct ManagePasscodeScreen: View {

    @Environment(\.router) var router
    @State private var isSet: Bool = false
    @State private var isBiometricEnabled: Bool = false
    @State private var biometricAvailability: BiometricAvailability = .available
    @State private var biometricError: String?
    @State private var showDisable = false
    /// Raised while the remove flow is actually rewriting key material, which is
    /// the one stretch the sheet must not be dismissable over.
    @State private var isRemoving = false

    private let service: PasscodeService

    init(service: PasscodeService = .shared) {
        self.service = service
    }

    /// The rows on offer, which depend on whether a passcode exists. Kept as an
    /// array rather than branching in the view body so each row can tell the
    /// shared list container where it sits, which is what rounds the end rows
    /// and draws the separators between them.
    private var rows: [Row] {
        isSet ? [.change, .autoLock, .biometrics, .disable] : [.set]
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(spacing: .zero) {
                        ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                            rowView(for: row)
                                .commonListItemContainer(index: index, itemsCount: rows.count)
                        }
                    }
                    .commonListContainer()

                    if let biometricNote {
                        Text(biometricNote)
                            .font(Theme.fonts.caption12)
                            .foregroundStyle(Theme.colors.alertError)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier(AccessibilityID.Settings.biometricUnlockNote)
                    }

                    explanation
                }
            }
        }
        .screenTitle("passcodeManageTitle".localized)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
        // Not dismissable mid-removal. The swipe and the backdrop tap are
        // refused for the same reason the close button is disabled: leaving does
        // not stop the transition, it only means this list re-reads the passcode
        // while it is still there and never hears that it went.
        .crossPlatformSheet(isPresented: $showDisable, isDismissable: !isRemoving) {
            DisablePasscodeScreen(isPresented: $showDisable, isRemoving: $isRemoving)
                .presentationDragIndicator(.visible)
        }
        // `.onAppear` as well as `.task`: returning from the pushed set/change
        // screens does not re-run `.task`, and a stale `isSet` would keep
        // offering "Set passcode" after one had just been set.
        .task { await refresh() }
        .onAppear { Task { await refresh() } }
        // And the navigation path on top of both, but only where the two above
        // are not enough: on macOS neither lifecycle callback fires when a
        // pushed screen pops, and this view is not torn down either, so it keeps
        // the `isSet` it was built with and goes on offering "Set passcode" over
        // a passcode that now exists. The path is the one thing that provably
        // changes when the set or change screen dismisses itself, and it is
        // published, so a live subscription hears the return whether or not the
        // view is told it reappeared.
        //
        // Confined to macOS because it is not free: `Published` replays on
        // subscribe and fires again for every push and pop anywhere in the
        // stack, so on iOS — where `.onAppear` already works — it would only add
        // Keychain and biometry reads for a screen that is often not on top.
        #if os(macOS)
        .onReceive(router.$navPath) { _ in
            Task { await refresh() }
        }
        #endif
        .onChange(of: showDisable) { _, isShowing in
            guard !isShowing else { return }
            Task { await refresh() }
        }
    }

    /// What the biometric row currently has to say for itself, if anything.
    ///
    /// The standing reason comes first and does not need a tap to find: a device
    /// with nothing enrolled cannot hold the shortcut, and letting someone
    /// discover that only by flipping a switch that flips back is the behaviour
    /// this screen was reported for. A failure from an actual attempt replaces
    /// it, because that one is about what just happened.
    private var biometricNote: String? {
        if let biometricError { return biometricError }
        guard rows.contains(.biometrics) else { return nil }

        switch biometricAvailability {
        case .available:
            return nil
        case .notEnrolled:
            return "passcodeBiometricNotEnrolled".localized
        case .unavailable:
            return "passcodeBiometricNotAvailable".localized
        }
    }

    /// States plainly what the passcode does and does not do. Encryption is what
    /// the passcode buys — with none set the key shares sit in the clear, and
    /// removing it puts them back — and it is still not a backup, which a user
    /// who believes otherwise may relax their habits over.
    private var explanation: some View {
        Text("passcodeManageExplanation".localized)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    enum Row: Hashable {
        case set
        case change
        case autoLock
        case biometrics
        case disable

        /// The localization key rather than the localized string:
        /// `SettingToggleCell` localizes its own title, so the key is what has
        /// to travel for the biometric row.
        var titleKey: String {
            switch self {
            case .set: "passcodeSetTitle"
            case .change: "passcodeChangeTitle"
            case .autoLock: "passcodeAutoLockTitle"
            case .biometrics: "passcodeBiometricToggle"
            case .disable: "passcodeDisableNavTitle"
            }
        }
    }

    /// Biometrics is a toggle rather than a destination, so it renders as the
    /// app's standard toggle row instead of a navigation cell. Both go through
    /// the same list container, which is what keeps the separators and the
    /// rounded end rows consistent across the group.
    @ViewBuilder
    private func rowView(for row: Row) -> some View {
        switch row {
        case .biometrics:
            // A shortcut past the passcode, not a replacement — the passcode
            // always works, and turning this off never locks anyone out.
            SettingToggleCell(
                title: row.titleKey,
                icon: "faceid",
                isEnabled: Binding(
                    get: { isBiometricEnabled },
                    set: { newValue in Task { await setBiometric(enabled: newValue) } }
                )
            )
            .accessibilityIdentifier(AccessibilityID.Settings.biometricUnlockToggle)
        default:
            Button {
                handle(row)
            } label: {
                SettingsCommonOptionView(
                    icon: .lockPassword,
                    title: row.titleKey.localized,
                    type: .normal
                )
            }
        }
    }

    private func handle(_ row: Row) {
        switch row {
        case .set:
            router.navigate(to: SettingsRoute.setPasscode)
        case .change:
            router.navigate(to: SettingsRoute.changePasscode)
        case .autoLock:
            router.navigate(to: SettingsRoute.autoLock)
        case .disable:
            showDisable = true
        case .biometrics:
            // Rendered as a toggle, never as a tappable destination.
            break
        }
    }

    private func setBiometric(enabled: Bool) async {
        // Moved before the call, so the switch follows the finger instead of
        // snapping back for the length of a Keychain round trip and then
        // returning. `refresh()` below overwrites it with what actually
        // happened, so an optimistic value can never outlive the attempt.
        isBiometricEnabled = enabled
        biometricError = nil

        if enabled {
            // Enabling needs the data key in hand, so it can only be done while
            // unlocked. A failure leaves the toggle off rather than implying a
            // shortcut exists — and now says why, which is the whole of this
            // change: every one of these used to be swallowed, so a device with
            // nothing enrolled produced a switch that returned to off and no
            // explanation anywhere.
            do {
                try await service.enableBiometricUnlock()
            } catch {
                biometricError = Self.message(for: error)
            }
        } else {
            // A failure here leaves the copy in place, so the toggle must not
            // claim it is gone. `refresh()` re-reads it either way.
            do {
                try await service.disableBiometricUnlock()
            } catch {
                biometricError = "passcodeBiometricDisableFailed".localized
            }
        }
        await refresh()
    }

    /// Says what the user has to do, where there is anything they can do.
    @MainActor
    private static func message(for error: Error) -> String {
        switch error as? BiometricUnlockError {
        case .notEnrolled:
            return "passcodeBiometricNotEnrolled".localized
        case .unavailable:
            return "passcodeBiometricNotAvailable".localized
        default:
            break
        }

        // A passcode-side refusal is not about biometry at all — the app locked
        // mid-flight, or another transition holds the lease — and
        // `PasscodeViewModel` already has the wording for those.
        if let passcodeError = error as? PasscodeError {
            return PasscodeViewModel.message(for: passcodeError)
        }

        return "passcodeBiometricEnableFailed".localized
    }

    private func refresh() async {
        isSet = await service.isSet
        isBiometricEnabled = await service.isBiometricUnlockEnabled
        biometricAvailability = await service.biometricAvailability
    }
}
