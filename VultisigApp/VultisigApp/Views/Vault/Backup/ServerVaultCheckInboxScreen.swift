//
//  ServerVaultCheckInboxScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 07/09/2025.
//

import SwiftUI

struct ServerVaultCheckInboxScreen: View {
    @Binding var isPresented: Bool
    @State var presentEmailDialog = false

    private var emailOptions: [EmailOption] {
        return [
            EmailOption(url: URL(string: "message://")!, name: "Mail"),
            EmailOption(url: URL(string: "googlegmail://")!, name: "Gmail"),
            EmailOption(url: URL(string: "ms-outlook://")!, name: "Outlook"),
            EmailOption(url: URL(string: "ymail://")!, name: "Yahoo Mail"),
            EmailOption(url: URL(string: "protonmail://")!, name: "ProtonMail")
        ].filter { UIApplication.shared.canOpenURL($0.url) }
    }

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
                    Text("checkEmail")
                        .foregroundStyle(Theme.colors.textPrimary)
                        .font(Theme.fonts.bodySMedium)
                        .underline()
                        .onTapGesture {
                            presentEmailDialog.toggle()
                        }
                        .showIf(!emailOptions.isEmpty)
                }
                .padding(.horizontal, 16)
            }

            Spacer()

            PrimaryButton(
                title: "close".localized,
                type: .secondary
            ) { isPresented.toggle() }
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
    
    private func openApp(url: URL) {
        UIApplication.shared.open(url, options: [:])
    }
}

private struct EmailOption: Identifiable {
    var id: String { url.absoluteString }
    let url: URL
    let name: String
}
