//
//  ErrorMessageSheet.swift
//  VultisigApp
//

import SwiftUI

/// Full-screen sheet that surfaces the raw technical error behind a friendly
/// `ErrorView`. The trace is shown in a scrollable bordered card, can be copied
/// to the clipboard, and reported — "Report Bug" copies the trace and opens the
/// Vultisig Discord so the user can paste it.
struct ErrorMessageSheet: View {
    let rawError: String
    @Binding var isPresented: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        content
            .sheetContainer()
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
            .presentationBackground(Theme.colors.bgPrimary)
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("errorMessageTitle".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)

            ScrollView {
                Text(rawError)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(Theme.colors.bgSurface1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Theme.colors.border, lineWidth: 1)
            )

            HStack(spacing: 12) {
                PrimaryButton(title: "errorCopy".localized, leadingIcon: "copy", type: .secondary) {
                    ClipboardManager.copyToClipboard(rawError)
                }
                PrimaryButton(title: "errorReportBug".localized, type: .secondary) {
                    ClipboardManager.copyToClipboard(rawError)
                    openURL(StaticURL.DiscordVultisigURL)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.colors.bgPrimary)
        .crossPlatformToolbar(showsBackButton: false) {
            CustomToolbarItem(placement: .leading) {
                ToolbarButton(image: "x") {
                    isPresented = false
                }
            }
        }
    }
}

#Preview {
    ErrorMessageSheet(
        rawError: "javax.crypto.AEADBadTagException: error:1e000065:Cipher functions",
        isPresented: .constant(true)
    )
}
