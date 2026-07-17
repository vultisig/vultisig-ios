//
//  ReshareScreen.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/07/2026.
//

import SwiftUI
import RiveRuntime

struct ReshareScreen: View {
    @Environment(\.router) var router
    let vault: Vault

    @State private var showJoinReshare = false
    @State private var shouldJoinKeygen = false
    @State private var showBeforeYouReshareSheet = false
    @State private var animationVM: RiveViewModel?

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                header
                Spacer()
                animation
                Spacer()
                optionCards
            }
        }
        .screenTitle("")
        .onAppear {
            guard animationVM == nil else { return }
            animationVM = RiveViewModel(fileName: "review_devices", autoPlay: true)
            animationVM?.fit = .fitWidth
        }
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

    var animation: some View {
        ZStack(alignment: .top) {
            animationVM?.view()
                .if(isMacOS) {
                    $0.frame(idealWidth: 395, maxWidth: 395, alignment: .center)
                }
                .scaleEffect(x: 1.2, y: 1.2)
                .offset(y: -50)
            LinearGradient(
                colors: [Theme.colors.bgPrimary, Theme.colors.bgPrimary, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
        }
        .background(
            EllipticalGradient(
                 stops: [
                     Gradient.Stop(color: Theme.colors.devicesSelectionGlow.opacity(0.5), location: 0.00),
                     Gradient.Stop(color: Theme.colors.devicesSelectionGlow.opacity(0), location: 1.00)
                 ],
                 center: UnitPoint(x: 0.5, y: 0.5)
             )
             .frame(width: 360, height: 360)
             .blur(radius: 50)
             .opacity(0.2)
        )
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
        // A server-backed vault must collect its password first so the server
        // is registered and joins the session; otherwise peer discovery would
        // wait forever for a device that never connects. Every other vault
        // goes straight to peer discovery.
        if vault.hasServerSigner {
            router.navigate(to: KeygenRoute.fastVaultPassword(
                tssType: .Reshare,
                vault: vault,
                selectedTab: .secure,
                isExistingVault: true,
                singleKeygenType: nil
            ))
        } else {
            router.navigate(to: KeygenRoute.peerDiscovery(
                tssType: .Reshare,
                vault: vault,
                selectedTab: .secure,
                fastSignConfig: nil,
                keyImportInput: nil,
                setupType: nil,
                singleKeygenType: nil
            ))
        }
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
                    .chevronRightSmall,
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
