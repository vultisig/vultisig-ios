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
    @State private var isResolvingStart = false

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
        .withLoading(isLoading: $isResolvingStart)
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
        // Latch re-entry for every vault type so a double confirmation can't
        // push two destinations. The flag also drives the loading overlay while
        // the backend eligibility probe is in flight.
        guard !isResolvingStart else { return }
        isResolvingStart = true

        Task {
            // Only route to the password screen when the backend vault is
            // CONFIRMED present. The structural `server-*` signer alone is not
            // enough: a restored or stale vault can carry one with no backend
            // vault, and forcing it into the password screen would dead-end (the
            // password can never validate). `isEligibleForFastSign` returns
            // `false` whenever presence is unconfirmed — missing, throttled, a
            // backend/storage error, or unreachable (the backend answers 400 for
            // both "absent" and "storage error", so those can't be told apart) —
            // and every such case falls back to peer discovery rather than
            // forcing password entry.
            let isBackendConfirmedPresent = await FastVaultService.shared.isEligibleForFastSign(vault: vault)
            isResolvingStart = false
            switch Self.startReshareRoute(isBackendConfirmedPresent: isBackendConfirmedPresent) {
            case .fastVaultPassword:
                navigateToFastVaultPassword()
            case .peerDiscovery:
                navigateToPeerDiscovery()
            }
        }
    }

    private func navigateToFastVaultPassword() {
        router.navigate(to: KeygenRoute.fastVaultPassword(
            tssType: .Reshare,
            vault: vault,
            selectedTab: .secure,
            isExistingVault: true,
            singleKeygenType: nil
        ))
    }

    private func navigateToPeerDiscovery() {
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

    /// Where "Start reshare" routes once the pre-flight sheet is confirmed.
    enum ReshareStartRoute: Equatable {
        /// Backend vault confirmed present: collect the password so the server joins.
        case fastVaultPassword
        /// Presence unconfirmed (secure vault, restored/stale vault, or an
        /// unreachable backend): reshare the actual devices via peer discovery
        /// instead of dead-ending on a password that can never validate.
        case peerDiscovery
    }

    /// Routes to the FastVault password screen only when the backend vault is
    /// confirmed present. A structural `server-*` signer with an unconfirmed
    /// backend vault must NOT be forced into password validation.
    static func startReshareRoute(isBackendConfirmedPresent: Bool) -> ReshareStartRoute {
        isBackendConfirmedPresent ? .fastVaultPassword : .peerDiscovery
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
