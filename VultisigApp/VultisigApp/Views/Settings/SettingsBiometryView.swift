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
        content
    }

    var main: some View {
        ScrollView {
            VStack(spacing: 16) {
                enableCell
                passwordCell
            }
            .padding(.horizontal, 16)
        }
        .task {
            viewModel.setData(vault: vault)
        }
        .onChange(of: viewModel.password) { _, _ in
            viewModel.passwordChanged()
        }
        .safeAreaInset(edge: .bottom) {
            button
        }
        .alert(NSLocalizedString("wrongPassword", comment: ""), isPresented: $viewModel.isWrongPassword) {
            Button("OK", role: .cancel) { }
        }
    }

    var enableCell: some View {
        HStack {
            Text(NSLocalizedString("enableBiometrics", comment: ""))
                .foregroundColor(.neutral0)
                .font(.body16MontserratSemiBold)

            Spacer()

            Toggle("", isOn: $viewModel.isBiometryEnabled)
        }
        .frame(height: 46)
        .padding(.horizontal, 16)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.top, 16)
    }

    var passwordCell: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("enterFastSigningPassword", comment: ""))
                .font(.body14MontserratMedium)
                .foregroundColor(.neutral0)

            HiddenTextField(placeholder: "typeHere", password: $viewModel.password)
                .padding(.top, 8)
        }
    }

    var button: some View {
        return Button {
            Task {
                if await viewModel.validatePassword(vault: vault) {
                    dismiss()
                }
            }
        } label: {
            FilledButton(title: "save")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .disabled(!viewModel.isSaveEnabled)
        .opacity(!viewModel.isSaveEnabled ? 0.5 : 1)
    }
}
