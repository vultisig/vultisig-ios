//
//  MonthlyBackupView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 19.11.2024.
//

import SwiftUI

struct MonthlyBackupView: View {

    @Binding var isPresented: Bool

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
            backupButton
            dontRemindButton
        }
    }

    var header: some View {
        HStack {
            Spacer()
                .frame(width: 44)

            Spacer()

            VStack {
                Text("Don't forget to backup your\nvault shares and verify the completeness.")
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
            isPresented = false
        } label: {
            FilledButton(title: "Backup")
        }
        .padding(16)
        .buttonStyle(.plain)
    }

    var dontRemindButton: some View {
        Button {
            isPresented = false
        } label: {
            OutlineButton(title: "Don’t remind me again")
        }
        .padding(16)
        .buttonStyle(.plain)
    }

    OutlineButton(title: "createFolder")

}
