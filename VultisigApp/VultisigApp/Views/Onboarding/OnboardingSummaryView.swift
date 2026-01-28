//
//  OnboardingSummaryView.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 08.02.2025.
//

import SwiftUI
import RiveRuntime

struct OnboardingSummaryView: View {
    enum Kind: String, Identifiable {
        case initial
        case fast
        case secure
        case keyImport

        var id: String { rawValue }

        var animation: String {
            switch self {
            case .initial:
                return "quick_summary"
            case .fast:
                return "fastvault_summary"
            case .secure:
                return "securevault_summary"
            case .keyImport:
                return .empty
            }
        }
    }

    let kind: Kind
    let vault: Vault?
    let onDismiss: (() -> Void)?

    @Binding var isPresented: Bool

    @State var didAgree: Bool = false
    @State var animationVM: RiveViewModel? = nil
    @State var presentChainSelection: Bool = false

    var showChooseChainsButton: Bool {
        vault != nil && vault?.libType != .KeyImport
    }

    init(kind: Kind, isPresented: Binding<Bool>, onDismiss: (() -> Void)?, vault: Vault? = nil) {
        self.kind = kind
        self._isPresented = isPresented
        self.onDismiss = onDismiss
        self.vault = vault
    }

    var body: some View {
        Screen {
            VStack(spacing: 16) {
                animation
                disclaimer
                VStack(spacing: 8) {
                    startUsingVaultButton
                    Group {
                        orSeparator
                        chooseYourChainButton
                    }
                    .showIf(showChooseChainsButton)
                }
                .disabled(!didAgree)

            }
            .padding(.top, isMacOS ? 0 : 32)
            .background(BlurredBackground())
            .onAppear {
                setData()
            }
        }
        .crossPlatformSheet(isPresented: $presentChainSelection) {
            if let vault {
                VaultSelectChainScreen(
                    vault: vault,
                    preselectChains: false,
                    isPresented: $presentChainSelection
                ) {
                    isPresented = false
                    onDismiss?()
                }
            }
        }
        .applySheetSize(700, kind == .fast ? 650 : 750)
    }

    var animation: some View {
        Group {
            switch kind {
            case .initial, .fast:
                animationVM?.view()
            case .secure:
                BackupGuideAnimationView(vault: vault, type: .secure)
            case .keyImport:
                BackupGuideAnimationView(vault: vault, type: .keyImport)
            }
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
            Checkbox(isChecked: $didAgree, isExtended: false)

            Text(NSLocalizedString("secureVaultSummaryDiscalimer", comment: ""))
                .foregroundColor(Theme.colors.textPrimary)
                .font(Theme.fonts.bodySMedium)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
    }

    var startUsingVaultButton: some View {
        PrimaryButton(title: "startUsingVault") {
            isPresented = false
            onDismiss?()
        }
        .buttonStyle(.plain)
    }

    var chooseYourChainButton: some View {
        PrimaryButton(title: "chooseYourChains", type: .secondary) {
            presentChainSelection = true
        }
        .buttonStyle(.plain)
    }

    var orSeparator: some View {
        HStack(spacing: 16) {
            Separator(opacity: 0.2)

            Text(NSLocalizedString("or", comment: "").uppercased())
                .font(Theme.fonts.bodySMedium)
                .foregroundColor(Theme.colors.textPrimary)

            Separator(opacity: 0.2)
        }
    }

    private func setData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            animationVM = RiveViewModel(fileName: kind.animation)
            animationVM?.fit = .layout
        }
    }
}

#Preview {
    @Previewable @State var isPresented: Bool = false
    return VStack {

    }
    .crossPlatformSheet(isPresented: $isPresented) {
        OnboardingSummaryView(
            kind: .keyImport,
            isPresented: .constant(true),
            onDismiss: {}
        ).environmentObject(HomeViewModel())
    }
    .onAppear {
        isPresented = true
    }

}
