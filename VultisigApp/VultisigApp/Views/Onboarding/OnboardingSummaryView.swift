//
//  OnboardingSummaryView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.02.2025.
//

import SwiftUI
import RiveRuntime

struct OnboardingSummaryView: View {
    enum Kind {
        case initial
        case fast
        case secure

        var animation: String {
            switch self {
            case .initial:
                return "quick_summary"
            case .fast:
                return "fastvault_summary"
            case .secure:
                return "securevault_summary"
            }
        }
    }

    let kind: Kind
    let vault: Vault?
    let onDismiss: (() -> Void)?

    @Binding var isPresented: Bool

    @State var didAgree: Bool = false
    @State var animationVM: RiveViewModel? = nil

    init(kind: Kind, isPresented: Binding<Bool>, onDismiss: (() -> Void)?, vault: Vault? = nil) {
        self.kind = kind
        self._isPresented = isPresented
        self.onDismiss = onDismiss
        self.vault = vault
    }

    var body: some View {
        ZStack {
            Background()
            view
        }
    }

    var view: some View {
        VStack(spacing: 16) {
            Spacer()
            animation
            Spacer()
            disclaimer
            button
        }
        .padding(24)
        .onAppear {
            setData()
        }
    }

    var disclaimer: some View {
        Button {
            withAnimation {
                didAgree.toggle()
            }
        } label: {
            disclaimerLabel
        }
        .buttonStyle(.plain)
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
            onDismiss?()
        } label: {
            FilledButton(
                title: "startUsingVault",
                textColor: didAgree ? .blue600 : .textDisabled,
                background: didAgree ? .turquoise600 : .buttonDisabled
            )
        }
        .disabled(!didAgree)
        .buttonStyle(.plain)
    }
    
    private func setData() {
        animationVM = RiveViewModel(fileName: kind.animation)
    }
}
