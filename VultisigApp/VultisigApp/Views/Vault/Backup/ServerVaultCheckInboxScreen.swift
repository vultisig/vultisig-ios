//
//  ServerVaultCheckInboxScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/09/2025.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ServerVaultCheckInboxScreen: View {
    @Binding var isPresented: Bool
    var onClose: () -> Void
    @State var presentEmailDialog = false

    var body: some View {
        VStack {
            SheetHeaderView(title: "serverBackup".localized, isPresented: $isPresented)
                .padding(.top, 12)
            Spacer()

            VStack(spacing: 40) {
                Image("check-inbox")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 365)

                VStack(spacing: 16) {
                    Text("backupShareSent")
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.title1)
                    Text("weJustSentYourBackupShare")
                        .foregroundStyle(Theme.colors.textExtraLight)
                        .font(Theme.fonts.bodySMedium)
                        .multilineTextAlignment(.center)
                    Button {
                        onCheckEmail()
                    } label: {
                        Text("checkEmail")
                            .foregroundStyle(Theme.colors.textPrimary)
                            .font(Theme.fonts.bodySMedium)
                            .underline()
                    }.showIf(showCheckInboxButton)
                }
                .padding(.horizontal, 16)
            }

            Spacer()

            PrimaryButton(
                title: "close".localized,
                type: .secondary
            ) {
                onClose()
                isPresented.toggle()
            }
        }
        .confirmationDialog("Choose email app", isPresented: $presentEmailDialog) {
            ForEach(emailOptions) { option in
                Button(option.name) {
                    openApp(url: option.url)
                }
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

#if os(macOS)
private extension ServerVaultCheckInboxScreen {
    var emailOptions: [EmailOption] { [] }
    
    var showCheckInboxButton: Bool { true }
    
    func canOpenURL(_ url: URL) -> Bool {
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }
    
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
