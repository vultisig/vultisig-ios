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
        Screen(title: "serverBackup".localized) {
            VStack {
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
                            .foregroundStyle(Theme.colors.textTertiary)
                            .font(Theme.fonts.bodySMedium)
                            .multilineTextAlignment(.center)
                        Button {
                            onCheckEmail()
                        } label: {
                            Text("checkEmail")
                                .foregroundStyle(Theme.colors.textPrimary)
                                .font(Theme.fonts.bodySMedium)
                                .underline()
                        }
                        .showIf(showCheckInboxButton)
                        .buttonStyle(.plain)
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
        }
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
