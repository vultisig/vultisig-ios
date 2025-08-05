//
//  MonthlyBackupView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 19.11.2024.
//

import SwiftUI

struct MonthlyBackupView: View {

    @Binding var isPresented: Bool
    @Binding var isBackupPresented: Bool

    @AppStorage("monthlyReminderDate") var monthlyReminderDate: Date = Date()

    var view: some View {
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
                    .foregroundColor(.neutral0)
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
            isBackupPresented = true
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
