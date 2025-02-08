//
//  OnboardingSummaryView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.02.2025.
//

import SwiftUI
import RiveRuntime

struct OnboardingSummaryView: View {

    let animationVM = RiveViewModel(fileName: "quick_summary")

    @Binding var isPresented: Bool

    @State var didAgree: Bool = false

    @EnvironmentObject var accountViewModel: AccountViewModel

    var body: some View {
        ZStack {
            Background()

            view
        }

    }

    var view: some View {
        VStack(spacing: 16) {
            Spacer()
            animationVM.view()
            Spacer()
            disclaimer
            button
        }
        .padding(24)
    }

    var disclaimer: some View {
        Button {
            withAnimation {
                didAgree.toggle()
            }
        } label: {
            disclaimerLabel
        }
    }

    var disclaimerLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: didAgree ? "checkmark.circle" : "circle")
                .foregroundColor(.alertTurquoise)

            Text(NSLocalizedString("secureVaultSummaryDiscalimer", comment: ""))
                .foregroundColor(.neutral0)
                .font(.body14BrockmannMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
    }

    var button: some View {
        Button {
            isPresented = false
            accountViewModel.showOnboarding = false
        } label: {
            FilledButton(
                title: "startUsingVault",
                textColor: didAgree ? .blue600 : .textDisabled,
                background: didAgree ? .turquoise600 : .buttonDisabled
            )
        }
        .disabled(!didAgree)
    }

    private func moveToVaultView() {
        accountViewModel.showOnboarding = false
    }
}
