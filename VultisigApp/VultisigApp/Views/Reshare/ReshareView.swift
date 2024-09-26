//
//  ReshareView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 26.09.2024.
//

import SwiftUI

struct ReshareView: View {

    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Image("LogoWithTitle")
                    .resizable()
                    .frame(width: 140, height: 32)
            }
        }
    }

    var view: some View {
        VStack(spacing: 16) {
            Spacer()
            Spacer()
            title
            Spacer()
            disclaimer
            buttons
        }
    }

    var title: some View {
        VStack(spacing: 16) {
            Text("Reshare your vault")
                .font(.body24MontserratMedium)
                .foregroundColor(.neutral0)

            Text("Reshare can be used to refresh, expand or reduce the amount of devices in a Vault.")
                .font(.body14Montserrat)
                .foregroundColor(.neutral300)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 36)
    }

    var disclaimer: some View {
        OutlinedDisclaimer(text: "For all Reshare actions the threshold of devices is always required.", alignment: .center)
            .padding(.horizontal, 16)
    }

    var buttons: some View {
        VStack(spacing: 12) {
            Button {

            } label: {
                FilledButton(title: "Start Reshare")
            }

            Button {

            } label: {
                OutlineButton(title: "Start Reshare with Vultisigner")
            }

            Button {

            } label: {
                OutlineButton(title: "Join Reshare")
            }
        }
        .padding(.horizontal, 40)
    }
}
