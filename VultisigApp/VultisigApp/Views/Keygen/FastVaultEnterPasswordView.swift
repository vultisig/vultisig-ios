//
//  FastVaultEnterPasswordView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 12.09.2024.
//

import SwiftUI

struct FastVaultEnterPasswordView: View {
    @Binding var showFastVaultPassword: Bool
    @Binding var password: String

    @Environment(\.dismiss) var dismiss

    let onSubmit: (() -> Void)?

    var body: some View {
        ZStack {
            ZStack {
                Background()
                main
            }
        }
        .navigationBarBackButtonHidden(true)
#if os(iOS)
        .navigationBarTitleTextColor(.neutral0)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackSheetButton(showSheet: $showFastVaultPassword)
            }
        }
#endif

    }

    var main: some View {
        VStack {
#if os(macOS)
            headerMac
#endif
            view
        }
    }

    var headerMac: some View {
        GeneralMacHeader(title: "Password")
    }

    var view: some View {
        VStack {
            passwordField
            Spacer()
            disclaimer
            buttons
        }
#if os(macOS)
        .padding(.horizontal, 25)
#endif
    }

    var passwordField: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FastVault password")
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)

            textfield
        }
        .padding(.horizontal, 16)
        .padding(.top, 30)
    }

    var textfield: some View {
        HiddenTextField(placeholder: "enterPassword", password: $password)
            .padding(.top, 8)
    }

    var disclaimer: some View {
        OutlinedDisclaimer(text: "This Password decrypt your FastVault Share")
            .padding(.horizontal, 16)
    }

    var buttons: some View {
        VStack(spacing: 20) {
            saveButton
        }
        .padding(.top, 16)
        .padding(.bottom, 40)
        .padding(.horizontal, 16)
    }

    var saveButton: some View {
        Button(action: {
            onSubmit?()
            dismiss()
        }) {
            FilledButton(title: "Continue")
        }
        .opacity(isSaveButtonDisabled ? 0.5 : 1)
        .disabled(isSaveButtonDisabled)
    }

    var isSaveButtonDisabled: Bool {
        return password.isEmpty
    }
}

