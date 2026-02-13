//
//  ReviewYourVaultsScreen.swift
//  VultisigApp
//

import SwiftUI
import RiveRuntime

struct ReviewYourVaultsScreen: View {
    let vault: Vault
    let tssType: TssType
    let keygenCommittee: [String]
    let email: String?
    let keyImportInput: KeyImportInput?
    let isInitiateDevice: Bool

    @State var animationVM: RiveViewModel?

    @Environment(\.router) var router

    var body: some View {
        Screen(
            title: "",
            showNavigationBar: false,
            edgeInsets: .init(leading: 0, trailing: 0)
        ) {
            VStack(spacing: 0) {
                icon
                animation
                content
                Spacer()
                buttons
            }
        }
        .onAppear {
            animationVM = RiveViewModel(fileName: "review_devices", autoPlay: true)
        }
    }

    var icon: some View {
        VaultSetupStepIcon(state: .active, icon: "devices")
            .padding(.top, 24)
    }

    var animation: some View {
        animationVM?.view()
    }

    var content: some View {
        VStack(spacing: 12) {
            Text("reviewYourVaultDevices".localized)
                .font(Theme.fonts.title2)
                .foregroundStyle(Theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("makeSureCorrectDevices".localized)
                .font(Theme.fonts.bodySMedium)
                .foregroundStyle(Theme.colors.textTertiary)
                .multilineTextAlignment(.center)

            deviceList
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }

    var deviceList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(Array(keygenCommittee.enumerated()), id: \.offset) { index, deviceID in
                    ReviewDeviceCell(
                        id: deviceID,
                        index: index + 1,
                        isThisDevice: deviceID == vault.localPartyID
                    )
                }
            }
        }
        .padding(.top, 24)
    }

    var buttons: some View {
        VStack(spacing: 16) {
            PrimaryButton(title: "looksGood".localized) {
                navigateToOverview()
            }

            Button {
                handleSomethingsWrong()
            } label: {
                Text("somethingsWrong".localized)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundStyle(Theme.colors.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func navigateToOverview() {
        router.navigate(to: KeygenRoute.keyImportOverview(
            vault: vault,
            email: email,
            keyImportInput: keyImportInput,
            setupType: .secure(numberOfDevices: keygenCommittee.count)
        ))
    }

    private func handleSomethingsWrong() {
        if isInitiateDevice {
            router.replace(to: KeygenRoute.peerDiscovery(
                tssType: tssType,
                vault: vault,
                selectedTab: .secure,
                fastSignConfig: nil,
                keyImportInput: keyImportInput,
                setupType: .secure(numberOfDevices: keygenCommittee.count)
            ))
        } else {
            router.navigateToRoot()
        }
    }
}

#Preview {
    ReviewYourVaultsScreen(
        vault: .example,
        tssType: .Keygen,
        keygenCommittee: [
            "iPhone-ABC123",
            "MacBook Pro-DEF456",
            "iPad-GHI789"
        ],
        email: nil,
        keyImportInput: nil,
        isInitiateDevice: true
    )
}
