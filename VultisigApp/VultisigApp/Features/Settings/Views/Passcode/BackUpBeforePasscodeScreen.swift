//
//  BackUpBeforePasscodeScreen.swift
//  VultisigApp
//

import SwiftUI

/// Asks for a backup before the passcode goes on.
///
/// Setting a passcode encrypts every stored key share under a key this device
/// holds. Nothing about that is reversible from the outside: if the key goes and
/// the shares stay — a restore that did not carry the Keychain across is the
/// ordinary way — the `.vult` is what brings the vault back, and there is no
/// support path that substitutes for it.
///
/// So this is a prompt rather than a warning banner, and it is deliberately not
/// a gate: the app cannot actually tell whether a backup exists or is current.
/// ``Vault/isBackedUp`` is a flag set by any export or import and never cleared
/// by a later change, so treating it as proof would let a stale backup through
/// silently while nagging someone who has a perfectly good one on disk. Asking,
/// and taking the answer, is the honest version of a check the app cannot make.
struct BackUpBeforePasscodeScreen: View {

    /// Closing is done by the presenter's flag rather than `@Environment(\.dismiss)`.
    ///
    /// Below macOS 26 `crossPlatformSheet` is not a presentation at all — it
    /// renders this view as a sibling inside the presenter's own `ZStack` — so
    /// there is nothing there for `dismiss()` to close, and it would reach past
    /// this screen to the enclosing navigation stack instead. The flag is the
    /// one thing both sheet implementations agree on.
    @Binding var isPresented: Bool

    /// Takes the user to the backup flow instead of the passcode.
    let onBackUpNow: () -> Void
    /// Proceeds to set the passcode on the user's word that a backup exists.
    let onContinue: () -> Void

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                Spacer(minLength: 44)

                Image("AppLockBackupIllustration")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 286)
                    .frame(height: 190)

                Spacer(minLength: 46)

                Circle()
                    .fill(Theme.colors.bgSurface1)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Icon(.cloudUpload, color: Theme.colors.primaryAccent4, size: 18)
                    }
                    .overlay {
                        Circle().stroke(Theme.colors.borderLight, lineWidth: 1)
                    }

                header
                    .padding(.top, 28)

                Spacer(minLength: 24)

                buttons
            }
        }
        .screenBackButtonHidden()
        .screenIgnoresTopEdge()
        .screenToolbar {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: .xmark) {
                    isPresented = false
                }
            }
        }
        .applySheetSize(650, 786)
        .sheetStyle()
    }

    var header: some View {
        VStack(spacing: 10) {
            Text("passcodeBackupPromptTitle".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)

            Text("passcodeBackupPromptSubtitle".localized)
                .font(Theme.fonts.bodySRegular)
                .foregroundStyle(Theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 330)
    }

    var buttons: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: "passcodeBackupPromptBackUpNow", action: onBackUpNow)
                .accessibilityIdentifier(AccessibilityID.Settings.passcodeBackupPromptBackUpNow)

            PrimaryButton(
                title: "passcodeBackupPromptHasBackup",
                type: .secondary,
                action: onContinue
            )
            .accessibilityIdentifier(AccessibilityID.Settings.passcodeBackupPromptHasBackup)
        }
    }
}

#Preview {
    BackUpBeforePasscodeScreen(
        isPresented: .constant(true),
        onBackUpNow: {},
        onContinue: {}
    )
}
