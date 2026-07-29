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
    @State private var showDisable = false

    private let service: PasscodeService
    private let lockService: AppLockService

    init(service: PasscodeService = .shared, lockService: AppLockService = .shared) {
        self.service = service
        self.lockService = lockService
    }

    var body: some View {
        Screen {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    SettingsSectionContainerView {
                        VStack(spacing: .zero) {
                            if isSet {
                                row(title: "passcodeChangeTitle".localized, showSeparator: true) {
                                    router.navigate(to: SettingsRoute.changePasscode)
                                }
                                row(title: "passcodeAutoLockTitle".localized, showSeparator: true) {
                                    router.navigate(to: SettingsRoute.autoLock)
                                }
                                row(title: "passcodeDisableNavTitle".localized, showSeparator: false) {
                                    showDisable = true
                                }
                            } else {
                                row(title: "passcodeSetTitle".localized, showSeparator: false) {
                                    router.navigate(to: SettingsRoute.setPasscode)
                                }
                            }
                        }
                    }

                    explanation
                }
            }
        }
        .screenTitle("passcodeManageTitle".localized)
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

    /// States plainly what the passcode does and does not do. Key shares are
    /// encrypted whether or not a passcode is set — it controls access to the
    /// key, and a user who believes otherwise may relax their backup habits.
    private var explanation: some View {
        Text("passcodeManageExplanation".localized)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
    }

    private func row(title: String, showSeparator: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsCommonOptionView(
                icon: .lockPassword,
                title: title,
                type: .normal,
                showSeparator: showSeparator
            )
        }
    }

    private func refresh() async {
        isSet = await service.isSet
    }
}
