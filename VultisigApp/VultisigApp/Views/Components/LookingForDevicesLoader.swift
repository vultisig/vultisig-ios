//
//  LookingForDevicesLoader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-06-20.
//

import SwiftUI
import RiveRuntime

struct LookingForDevicesLoader: View {
    var tssType: TssType? = nil
    var selectedTab: SetupVaultState? = nil

    @State var animationVM: RiveViewModel? = nil

    @State var didSwitch = false

    var body: some View {
        ZStack {
            shadow
            content
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cornerRadius(10)
        .onAppear {
            animationVM = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                didSwitch.toggle()
            }
        }
        .onDisappear {
            animationVM?.stop()
        }
    }

    var shadow: some View {
        Circle()
            .frame(width: 360, height: 360)
            .foregroundColor(Theme.colors.alertInfo)
            .opacity(0.02)
            .blur(radius: 20)
            .clipped()
    }

    var content: some View {
        VStack {
            Spacer()
            loader

            if selectedTab == .fast {
                fastContent
            } else {
                title
            }

            Spacer()
        }
    }

    var title: some View {
        Text(getTitle())
            .font(Theme.fonts.bodySRegular)
            .foregroundColor(Theme.colors.textPrimary)
            .bold()
            .multilineTextAlignment(.center)
    }

    var fastContent: some View {
        VStack {
            Text(NSLocalizedString("connectingWithServer...", comment: ""))
                .font(Theme.fonts.title2)

            Text(NSLocalizedString("shouldOnlyTakeAMinute...", comment: ""))
                .font(Theme.fonts.bodySMedium)
        }
        .foregroundColor(Theme.colors.textSecondary)
    }

    var loader: some View {
        animationVM?.view()
            .frame(width: 24, height: 24)
    }

    private func getTitle() -> String {
        if let tssType, tssType == .Reshare {
            return NSLocalizedString("resharingLoaderTitle", comment: "")
        } else if let selectedTab {
            return selectedTab.loaderTitle
        } else {
            return NSLocalizedString("lookingForDevices", comment: "Looking for devices")
        }
    }
}

#Preview {
    ZStack {
        Background()
        LookingForDevicesLoader(tssType: .Reshare, selectedTab: .secure)
    }
}
