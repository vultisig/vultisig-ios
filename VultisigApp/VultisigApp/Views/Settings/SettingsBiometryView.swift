//
//  SettingsBiometryView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 16.10.2024.
//

import SwiftUI

struct SettingsBiometryView: View {

    @Environment(\.dismiss) var dismiss

    @StateObject var viewModel = SettingsBiometryViewModel()

    let vault: Vault

    var body: some View {
        ZStack {
            Background()
            main

            if viewModel.isLoading {
                Loader()
            }
        }
        .navigationTitle(NSLocalizedString("enableBiometrics", comment: ""))
    }

    var view: some View {
        ScrollView {
            VStack(spacing: 16) {
                enableCell

                if viewModel.isBiometryEnabled {
                    passwordCell
                }

                hintCell
            }
            .padding(.horizontal, 16)
        }
//        .task {
//            viewModel.setData(vault: vault)
//        }
        .safeAreaInset(edge: .bottom) {
            button
        }
//        .alert(NSLocalizedString("wrongPassword", comment: ""), isPresented: $viewModel.isWrongPassword) {
//            Button("OK", role: .cancel) { }
//        }
    }

    var enableCell: some View {
        HStack {
            Text(NSLocalizedString("enableBiometrics", comment: ""))
                .foregroundColor(Theme.colors.textPrimary)
                .font(Theme.fonts.bodyMMedium)

            Spacer()

            Toggle("", isOn: Binding(get: {
                viewModel.isBiometryEnabled
            }, set: {
                viewModel.onBiometryEnabledChanged($0, vault: vault) }))
        }
        .frame(height: 46)
        .padding(.horizontal, 16)
        .background(Theme.colors.bgSecondary)
        .cornerRadius(10)
        .padding(.top, 16)
    }

    var passwordCell: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("enterFastSigningPassword", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)

            HiddenTextField(placeholder: "typeHere", password: $viewModel.password,errorMessage: "")
                .padding(.top, 8)
        }
    }

    var hintCell: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("passwordHintTitle", comment: ""))
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)

            HiddenTextField(
                placeholder: "typeHere",
                password: $viewModel.hint,
                showHideOption: false,
                errorMessage: ""
            )
            .padding(.top, 8)
        }
    }

    var button: some View {
        PrimaryButton(title: "save") {
            Task {
                if await viewModel.validateForm(vault: vault) {
                    dismiss()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .disabled(!viewModel.isSaveEnabled)
        .opacity(!viewModel.isSaveEnabled ? 0.5 : 1)
    }
}
