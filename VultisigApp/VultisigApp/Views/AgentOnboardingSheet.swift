//
//  AgentOnboardingSheet.swift
//  VultisigApp
//

import SwiftUI

struct AgentOnboardingSheet: View {
    @Binding var isPresented: Bool

    let onAuthorize: () -> Void

    var body: some View {
        ZStack {
            Background()
            content
        }
        .presentationDetents([.height(460)])
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        VStack(spacing: 32) {
            image
            text
            VStack(spacing: 20) {
                buttons
                learnMore
            }
        }
        .padding(.bottom, 8)
    }

    private var image: some View {
        Image("agent-onboarding")
            .resizable()
            .scaledToFit()
            .frame(height: 200)
            .edgesIgnoringSafeArea(.top)
    }

    private var text: some View {
        VStack(spacing: 12) {
            Text("agentOnboardingTitle".localized)
                .font(Theme.fonts.title3)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("agentOnboardingDescription".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            PrimaryButton(title: "agentOnboardingNotNow".localized, type: .outline) {
                isPresented = false
            }

            PrimaryButton(title: "agentOnboardingAuthorize".localized) {
                onAuthorize()
                isPresented = false
            }
        }
        .padding(.horizontal, 16)
    }

    private var learnMore: some View {
        Button {
            // TODO: Add learn more URL
        } label: {
            Text("agentOnboardingLearnMore".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
                .underline()
        }
    }
}

#Preview {
    Screen {
        VStack {}
    }
    .crossPlatformSheet(isPresented: .constant(true)) {
        AgentOnboardingSheet(isPresented: .constant(true)) {}
    }
}
