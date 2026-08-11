//
//  KeyshareRecoveryScreen.swift
//  VultisigApp
//

import SwiftUI

/// Shown when this device holds sealed key shares and the key that opens them is
/// confirmed gone.
///
/// The state is real and legitimate: an iOS restore from an *unencrypted*
/// computer backup carries the SwiftData store but not the Keychain item, so the
/// vaults arrive without the key that unseals them. Names, addresses and
/// balances all still render, and only signing fails — which is why this screen
/// exists rather than a silent open.
///
/// Three rules shape the copy, and each one is a way of making it worse:
///
/// 1. **No blame and no alarm.** Nothing the user did caused this, and telling
///    them their funds are gone when a `.vult` would bring them straight back is
///    the wrong instruction at the worst moment.
/// 2. **The `.vult` is named, and importing it is one tap away.** It is the only
///    route back for a device that has lost the key, so it is the primary action
///    rather than a sentence someone has to interpret.
/// 3. **No reinstall or clear-data advice, anywhere.** That is the one action
///    that turns a recoverable vault into an unrecoverable one — it removes the
///    stored shares as well, so a user who later finds their backup has nothing
///    left to reconcile it against.
struct KeyshareRecoveryScreen: View {

    /// Hands the user to the app's import flow. Held as a closure because this
    /// screen is mounted in a window above the app's own hierarchy, which
    /// carries none of its navigation.
    let onRestoreFromBackup: () -> Void

    /// Whether the honest statement for the user with no backup is showing.
    ///
    /// Behind a disclosure rather than on the face of the screen: it is the one
    /// genuinely bad outcome, and leading with it would tell everyone their
    /// vaults are gone when most of them are one file away from having them
    /// back.
    @State private var isShowingNoBackupHelp = false

    var body: some View {
        Screen {
            VStack(spacing: 24) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                        noBackupSection
                    }
                    .frame(maxWidth: .infinity)
                }

                PrimaryButton(title: "keyshareRecoveryImportButton".localized) {
                    onRestoreFromBackup()
                }
                .accessibilityIdentifier(AccessibilityID.Passcode.keyshareRecoveryImportButton)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .screenNavigationBarHidden(true)
        .screenBackground(.gradient)
        .accessibilityIdentifier(AccessibilityID.Passcode.keyshareRecoveryScreen)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Icon(.folderLock, color: Theme.colors.alertWarning, size: 48)
                .padding(.bottom, 8)

            Text("keyshareRecoveryTitle".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)

            Text("keyshareRecoveryMessage".localized)
                .font(Theme.fonts.bodyMRegular)
                .foregroundStyle(Theme.colors.textTertiary)

            Text("keyshareRecoveryBackupMessage".localized)
                .font(Theme.fonts.bodyMMedium)
                .foregroundStyle(Theme.colors.textPrimary)
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        // The paragraphs wrap to whatever height they need instead of being
        // compressed into one truncated line: the sentence naming the `.vult` is
        // the last thing on this screen that should end in an ellipsis.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 24)
    }

    private var noBackupSection: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation { isShowingNoBackupHelp.toggle() }
            } label: {
                Text("keyshareRecoveryNoBackupTitle".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.primaryAccent4)
                    .underline()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityID.Passcode.keyshareRecoveryNoBackupToggle)

            if isShowingNoBackupHelp {
                Text("keyshareRecoveryNoBackupMessage".localized)
                    .font(Theme.fonts.bodySRegular)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(Theme.radius.md.shape.fill(Theme.colors.bgSurface2))
            }
        }
        .padding(.top, 16)
    }
}

#Preview {
    KeyshareRecoveryScreen(onRestoreFromBackup: {})
}
