//
//  ReshareScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/07/2026.
//

import SwiftUI

struct ReshareScreen: View {
    @Environment(\.router) var router
    let vault: Vault

    @State private var showJoinReshare = false
    @State private var shouldJoinKeygen = false
    @State private var showBeforeYouReshareSheet = false

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                header
                Spacer()
                illustration
                Spacer()
                optionCards
            }
        }
        .screenTitle("")
        .bottomSheet(isPresented: $showBeforeYouReshareSheet) {
            BeforeYouReshareBottomSheet {
                showBeforeYouReshareSheet = false
                onStartReshareConfirmed()
            }
        }
        #if os(iOS)
        .onChange(of: shouldJoinKeygen) { _, shouldNavigate in
            guard shouldNavigate else { return }
            router.navigate(to: OnboardingRoute.joinKeygen(
                vault: vault,
                selectedVault: nil
            ))
            shouldJoinKeygen = false
        }
        .crossPlatformSheet(isPresented: $showJoinReshare) {
            GeneralCodeScannerView(
                showSheet: $showJoinReshare,
                selectedChain: .constant(nil),
                onJoinKeygen: {
                    shouldJoinKeygen = true
                }
            )
        }
        #endif
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("reshareLabelTitle".localized)
                .font(Theme.fonts.title1)
                .foregroundStyle(Theme.colors.textPrimary)

            Text("reshareVaultSubtitle".localized)
                .font(Theme.fonts.footnote)
                .foregroundStyle(Theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
    }

    var illustration: some View {
        Image("reshare-devices")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 300)
            .background(glow)
    }

    var glow: some View {
        EllipticalGradient(
            stops: [
                Gradient.Stop(color: Color(hex: "084BFF").opacity(0.5), location: 0.00),
                Gradient.Stop(color: Color(hex: "084BFF").opacity(0), location: 1.00)
            ],
            center: UnitPoint(x: 0.5, y: 0.5)
        )
        .frame(width: 360, height: 360)
        .blur(radius: 36)
    }

    var optionCards: some View {
        VStack(spacing: 10) {
            ReshareOptionCard(
                title: "startReshare".localized,
                subtitle: "startReshareSubtitle".localized,
                action: onStartReshare
            )

            ReshareOptionCard(
                title: "joinReshare".localized,
                subtitle: "joinReshareSubtitle".localized,
                action: onJoinReshare
            )
        }
    }

    private func onStartReshare() {
        showBeforeYouReshareSheet = true
    }

    private func onStartReshareConfirmed() {
        router.navigate(to: VaultRoute.reshareDeviceCount(vault: vault))
    }

    private func onJoinReshare() {
        #if os(macOS)
        router.navigate(to: KeygenRoute.macScanner(
            type: .NewVault,
            selectedVault: nil
        ))
        #else
        showJoinReshare = true
        #endif
    }
}

private struct ReshareOptionCard: View {
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(Theme.fonts.title3)
                        .foregroundStyle(Theme.colors.textPrimary)

                    Text(subtitle)
                        .font(Theme.fonts.footnote)
                        .foregroundStyle(Theme.colors.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Icon(
                    named: "chevron-right-small",
                    color: Theme.colors.textPrimary,
                    size: 20
                )
            }
            .padding(24)
            .background(Theme.colors.bgSurface1)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Theme.colors.borderLight, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ReshareScreen(vault: Vault.example)
}
