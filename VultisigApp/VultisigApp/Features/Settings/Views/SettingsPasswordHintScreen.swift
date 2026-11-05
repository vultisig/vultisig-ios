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
                        Text("editPasswordHintSubtitle".localized)
                            .settingsText(.bodyS)
                            .foregroundStyle(Theme.colors.textTertiary)

                        CommonTextEditor(
                            value: $viewModel.hint,
                            placeholder: "settingsEnterHint".localized,
                            isFocused: $isFocused,
                            appearance: .settingsInput
                        )
                    }
                }

                PrimaryButton(title: "save", size: .compactSemibold) {
                    viewModel.saveHint(vault: vault)
                    dismiss()
                }
                .disabled(!viewModel.saveHintEnabled)
            }
        }
        .screenTitle("editPasswordHintTitle".localized)
        .onAppear(perform: onAppear)
    }

    func onAppear() {
        viewModel.resetHintData(vault: vault)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isFocused = true
        }
    }
}
