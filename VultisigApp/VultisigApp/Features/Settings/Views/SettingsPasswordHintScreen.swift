//
//  SettingsPasswordHintScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 03/09/2025.
//

import SwiftUI

struct SettingsPasswordHintScreen: View {
    @Environment(\.dismiss) var dismiss
    let vault: Vault
    @ObservedObject var viewModel: SettingsBiometryViewModel

    @FocusState var isFocused

    var body: some View {
        Screen {
            VStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("editPasswordHintTitle".localized)
                            .font(Theme.fonts.largeTitle)
                            .foregroundColor(Theme.colors.textPrimary)
                            .padding(.top, 12)

                        Text("editPasswordHintSubtitle".localized)
                            .font(Theme.fonts.bodySMedium)
                            .foregroundColor(Theme.colors.textTertiary)

                        CommonTextEditor(
                            value: $viewModel.hint,
                            placeholder: "enterHint".localized,
                            isFocused: $isFocused
                        ) {}
                    }
                }

                PrimaryButton(title: "save".localized) {
                    viewModel.saveHint(vault: vault)
                    dismiss()
                }
                .disabled(!viewModel.saveHintEnabled)
            }
        }
        .onAppear(perform: onAppear)
    }

    func onAppear() {
        viewModel.resetHintData(vault: vault)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isFocused = true
        }
    }
}
