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

    @State private var animationVM: RiveViewModel?
    @State private var size: CGFloat?
    let animationHeight: CGFloat = 280
    var animationOffset: CGFloat {
        isMacOS ? -100 : 0
    }
    
    @Environment(\.router) var router

    var body: some View {
        Screen(
            title: "",
            edgeInsets: .init(top: 0, leading: 0, trailing: 0)
        ) {
            VStack(spacing: 24) {
                Spacer().frame(height: animationHeight + animationOffset)
                VStack(spacing: 8) {
                    content
                    buttons
                }
            }
            .background(animation, alignment: .top)
            .ignoresSafeArea()
        }
        .readSize { size = $0.width }
        .onAppear {
            animationVM = RiveViewModel(fileName: "review_devices", autoPlay: true)
            animationVM?.fit = .fitWidth
        }
    }
    
    var animation: some View {
        ZStack(alignment: .top) {
            animationVM?.view()
                .frame(idealWidth: 395, maxWidth: 395, alignment: .center)
                .showIf(size != 0)
            LinearGradient(
                colors: [Theme.colors.bgPrimary, Theme.colors.bgPrimary, .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(width: 50, height: 120)
        }
        .frame(height: animationHeight)
        .offset(y: animationOffset)
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
    }

    private func navigateToOverview() {
        router.navigate(to: KeygenRoute.keyImportOverview(
            tssType: tssType,
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
