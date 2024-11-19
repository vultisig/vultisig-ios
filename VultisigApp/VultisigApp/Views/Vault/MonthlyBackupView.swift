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

    var body: some View {
        ZStack {
            Background()
            view
        }
        .onAppear {
            monthlyReminderDate = Date()
        }
    }

    var view: some View {
        VStack(spacing: 0) {
            header
            Spacer()

            VStack(spacing: 16) {
                backupButton
                dontRemindButton
            }
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
                    .font(.body16MontserratSemiBold)
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
        Button {
            isBackupPresented = true
            isPresented = false
        } label: {
            FilledButton(title: "backup")
        }
        .padding(.horizontal, 16)
        .buttonStyle(.plain)
    }

    var dontRemindButton: some View {
        Button {
            monthlyReminderDate = .distantFuture
            isPresented = false
        } label: {
            OutlineButton(title: "dontRemind")
        }
        .padding(.horizontal, 16)
        .buttonStyle(.plain)
    }
}
