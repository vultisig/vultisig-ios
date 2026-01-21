//
//  BackupVaultWarningView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 25.10.2024.
//

import SwiftUI

struct BackupVaultWarningView: View {

    @Binding var isPresented: Bool
    @Binding var isSkipPressed: Bool

    @State var isChecked: Bool = false

    var body: some View {
        ZStack {
            Background()
            view
        }
    }

    var view: some View {
        VStack {
            header
            Spacer()
            checkbox
            Spacer()
            skipButton
        }
    }

    var header: some View {
        HStack {
            Button {
                isPresented = false
            } label: {
                Image("x")
            }
            .padding(16)
            .offset(y: 2)
            .buttonStyle(.plain)

            Spacer()

            Text("Skip Backup")
                .foregroundColor(Theme.colors.textPrimary)
                .font(Theme.fonts.bodyLMedium)

            Spacer()
            Spacer()
                .frame(width: 44)
        }
        .frame(height: 70)
    }

    var checkbox: some View {
        Checkbox(
            isChecked: $isChecked,
            text: "backupNowCheckbox",
            font: Theme.fonts.bodySMedium,
            alignment: .leading
        )
        .padding(.horizontal, 28)
    }

    var skipButton: some View {
        PrimaryButton(title: "Skip Backup") {
            isPresented = false
            isSkipPressed = true
        }
        .disabled(!isChecked)
        .opacity(!isChecked ? 0.5 : 1.0)
        .padding(16)
        .buttonStyle(.plain)
    }
}
