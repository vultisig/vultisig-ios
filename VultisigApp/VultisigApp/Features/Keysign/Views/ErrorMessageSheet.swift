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
        main
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.colors.bgPrimary.ignoresSafeArea())
            #if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
    }

    var main: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("errorMessageTitle".localized)
                    .font(Theme.fonts.title2)
                    .foregroundStyle(Theme.colors.textPrimary)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(Theme.fonts.bodyMMedium)
                        .foregroundStyle(Theme.colors.textPrimary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                Text(rawError)
                    .font(Theme.fonts.footnote)
                    .foregroundStyle(Theme.colors.textTertiary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .frame(maxHeight: 420)
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
                PrimaryButton(title: "errorCopy".localized, type: .secondary) {
                    ClipboardManager.copyToClipboard(rawError)
                }
                PrimaryButton(title: "errorReportBug".localized, type: .secondary) {
                    ClipboardManager.copyToClipboard(rawError)
                    openURL(StaticURL.DiscordVultisigURL)
                }
            }

            Spacer()
        }
    }
}

#Preview {
    ErrorMessageSheet(
        rawError: "javax.crypto.AEADBadTagException: error:1e000065:Cipher functions",
        isPresented: .constant(true)
    )
}
