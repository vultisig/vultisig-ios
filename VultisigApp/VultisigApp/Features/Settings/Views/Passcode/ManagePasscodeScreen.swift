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
    @State private var showDisable = false

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

                    explanation
                }
            }
        }
        .screenTitle("passcodeManageTitle".localized)
        .screenBackground(.gradient)
        .screenEdgeInsets(ScreenEdgeInsets(bottom: 0))
        .crossPlatformSheet(isPresented: $showDisable) {
            DisablePasscodeScreen()
        }
        // `.onAppear` as well as `.task`: returning from the pushed set/change
        // screens does not re-run `.task`, and a stale `isSet` would keep
        // offering "Set passcode" after one had just been set.
        .task { await refresh() }
        .onAppear { Task { await refresh() } }
        .onChange(of: showDisable) { _, isShowing in
            guard !isShowing else { return }
            Task { await refresh() }
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
        if enabled {
            // Enabling needs the data key in hand, so it can only be done while
            // unlocked. A failure leaves the toggle off rather than implying a
            // shortcut exists.
            do {
                try await service.enableBiometricUnlock()
            } catch {
                isBiometricEnabled = false
                return
            }
        } else {
            // A failure here leaves the copy in place, so the toggle must not
            // claim it is gone.
            try? await service.disableBiometricUnlock()
        }
        await refresh()
    }

    private func refresh() async {
        isSet = await service.isSet
        isBiometricEnabled = await service.isBiometricUnlockEnabled
    }
}
