//
//  MonthlyBackupView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 19.11.2024.
//

import SwiftUI

struct MonthlyBackupView: View {

    @Binding var isPresented: Bool
    let onBackup: () -> Void

    @AppStorage("monthlyReminderDate") var monthlyReminderDate: Date = Date()

    var body: some View {
        ZStack {
            Background()
            content
                #if os(macOS)
                .padding(.bottom, 30)
                #endif
        }
    }

    var content: some View {
        VStack(spacing: 0) {
            header
            Spacer()

            VStack(spacing: 16) {
                backupButton
                dontRemindButton
            }
        }
        .onAppear {
            monthlyReminderDate = Date()
        }
    }

    var header: some View {
        HStack {
            Spacer()
                .frame(width: 44)

            Spacer()

            VStack {
                Text(NSLocalizedString("monthlyBackupTitle", comment: ""))
                    .foregroundColor(Theme.colors.textPrimary)
                    .font(Theme.fonts.bodyMMedium)
                    .multilineTextAlignment(.center)

                Spacer()
            }

            Spacer()

            VStack {
                Button {
                    isPresented = false
                } label: {
                    Image("x")
                }
                .padding(.horizontal, 16)
                .offset(y: 2)
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.top, 30)
    }

    var backupButton: some View {
        PrimaryButton(title: "backup") {
            onBackup()
            isPresented = false
        }
        .padding(.horizontal, 16)
        .buttonStyle(.plain)
    }

    var dontRemindButton: some View {
        PrimaryButton(title: "dontRemind", type: .secondary) {
            monthlyReminderDate = .distantFuture
            isPresented = false
        }
        .padding(.horizontal, 16)
    }
}
