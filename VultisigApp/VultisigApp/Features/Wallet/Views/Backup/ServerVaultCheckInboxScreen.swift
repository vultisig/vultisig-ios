//
//  ServerVaultCheckInboxScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/09/2025.
//

import SwiftUI
import VultisigUIResources
#if os(macOS)
import AppKit
#endif

struct ServerVaultCheckInboxScreen: View {
    @Binding var isPresented: Bool
    var onClose: () -> Void
    @State var presentEmailDialog = false

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                VultisigImage("check-inbox")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 250)

                Spacer()

                VStack(spacing: 16) {
                    Text("backupShareSent")
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.title1)
                    Text("weJustSentYourBackupShare")
                        .foregroundStyle(Theme.colors.textTertiary)
                        .settingsText(.bodyS)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 275)
                    Button {
                        onCheckEmail()
                    } label: {
                        Text("checkEmail")
                            .foregroundStyle(Theme.colors.textSecondary)
                            .settingsText(.bodyS)
                            .underline()
                    }
                    .showIf(showCheckInboxButton)
                    .buttonStyle(.plain)
                }

                Spacer()

                PrimaryButton(
                    title: "close".localized,
                    type: .secondary,
                    size: .compactSemibold
                ) {
                    onClose()
                    isPresented.toggle()
                }
                .padding(.horizontal, 17)
            }
        }
        .screenTitle("serverBackup".localized)
        .sheetStyle()
        .applySheetSize()
        .confirmationDialog("chooseEmailApp".localized, isPresented: $presentEmailDialog) {
            ForEach(emailOptions) { option in
                Button(option.name) {
                    openApp(url: option.url)
                }
            }
            Button("cancel".localized, role: .cancel) { }
        }
    }
}

#if os(macOS)
private extension ServerVaultCheckInboxScreen {
    var emailOptions: [EmailOption] { [] }

    var showCheckInboxButton: Bool { true }

    func openApp(url: URL) {
        NSWorkspace.shared.open(url)
    }

    func onCheckEmail() {
        NSWorkspace.shared.open(URL(string: "mailto:")!)
    }
}
#else
private extension ServerVaultCheckInboxScreen {
    var showCheckInboxButton: Bool { !emailOptions.isEmpty }

    func openApp(url: URL) {
        UIApplication.shared.open(url, options: [:])
    }

    var emailOptions: [EmailOption] {
        [
            EmailOption(url: URL(string: "message://")!, name: "Mail"),
            EmailOption(url: URL(string: "googlegmail://")!, name: "Gmail"),
            EmailOption(url: URL(string: "ms-outlook://")!, name: "Outlook"),
            EmailOption(url: URL(string: "ymail://")!, name: "Yahoo Mail"),
            EmailOption(url: URL(string: "protonmail://")!, name: "ProtonMail")
        ].filter { UIApplication.shared.canOpenURL($0.url) }
    }

    func onCheckEmail() {
        presentEmailDialog.toggle()
    }
}
#endif

private struct EmailOption: Identifiable {
    var id: String { url.absoluteString }
    let url: URL
    let name: String
}
