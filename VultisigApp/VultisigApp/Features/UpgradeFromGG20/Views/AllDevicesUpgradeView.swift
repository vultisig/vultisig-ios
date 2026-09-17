//
//  AllDevicesUpgradeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-04-11.
//

import SwiftUI
import RiveRuntime

struct AllDevicesUpgradeView: View {
    let vault: Vault
    var hasReviewedBackups = false

    @State var animationVM: RiveViewModel? = nil
    @Environment(\.router) var router

    var body: some View {
        ZStack {
            Background()
            content
        }
        .onAppear {
            setData()
        }
    }

    #if os(iOS)
    var content: some View {
        VStack(spacing: 0) {
            Spacer()
            animation
            Spacer()
            description
            button
        }
        .padding(36)
        .toolbar {
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationHelpButton()
            }
        }
    }
    #endif

    var animation: some View {
        animationVM?.view()
    }

    var description: some View {
        Group {
            Text(NSLocalizedString("allDevicesUpgradeTitle1", comment: ""))
                .foregroundStyle(Theme.colors.textPrimary) +
            Text(NSLocalizedString("allDevicesUpgradeTitle2", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString("allDevicesUpgradeTitle3", comment: ""))
                .foregroundStyle(Theme.colors.textPrimary)
        }
        .multilineTextAlignment(.center)
        .font(Theme.fonts.title1)
    }

    var button: some View {
        PrimaryButton(title: "next") {
            router.navigate(to: nextRoute)
        }
        .frame(width: 120)
        .padding(.vertical, 36)
    }

    /// Switching to paired after the backup instructions should show the
    /// all-devices guidance once, then continue directly to discovery.
    var nextRoute: any NavPath {
        if hasReviewedBackups {
            return KeygenRoute.peerDiscovery(
                tssType: .Migrate,
                vault: vault,
                selectedTab: .secure,
                fastSignConfig: nil,
                keyImportInput: nil,
                setupType: nil,
                singleKeygenType: nil
            )
        }
        return VaultRoute.vaultShareBackups(vault: vault)
    }

    private func setData() {
        animationVM = RiveViewModel(fileName: "all_devices_animation", autoPlay: true)
    }
}

#Preview {
    AllDevicesUpgradeView(vault: Vault.example)
}

#if os(macOS)
extension AllDevicesUpgradeView {
    var content: some View {
        VStack {
            Spacer()
            animation
            Spacer()
            description
            button
        }
        .crossPlatformToolbar("Upgrade")
        .padding(.bottom, 30)
    }
}
#endif
