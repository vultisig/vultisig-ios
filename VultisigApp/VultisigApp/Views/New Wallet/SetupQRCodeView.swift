//
//  SetupQRCodeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftData
import SwiftUI

struct SetupQRCodeView: View {
    let tssType: TssType
    let vault: Vault?

    @State var selectedTab: SetupVaultState = .fast
    @State var showSheet: Bool = false
    @State var shouldJoinKeygen = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.router) var router

    var body: some View {
        content
            .sensoryFeedback(.selection, trigger: selectedTab)
    }

    var view: some View {
        VStack {
            tabView
            button
        }
    }

    var tabView: some View {
        SetupVaultTabView(selectedTab: $selectedTab)
    }

    var button: some View {
        startButton
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
    }

    var startButton: some View {
        PrimaryButton(title: "next") {
            if tssType == .Keygen {
                router.navigate(to: KeygenRoute.newWalletName(
                    tssType: tssType,
                    selectedTab: selectedTab,
                    name: Vault.getUniqueVaultName(modelContext: modelContext, state: selectedTab)
                ))
            } else if let vault {
                if selectedTab.isFastVault {
                    router.navigate(to: KeygenRoute.fastVaultEmail(
                        tssType: tssType,
                        vault: vault,
                        selectedTab: selectedTab,
                        fastVaultExist: false
                    ))
                } else {
                    router.navigate(to: KeygenRoute.peerDiscovery(
                        tssType: tssType,
                        vault: vault,
                        selectedTab: selectedTab,
                        fastSignConfig: nil,
                        keyImportInput: nil,
                        setupType: nil
                    ))
                }
            }
        }
    }
}

#Preview {
    SetupQRCodeView(
        tssType: .Keygen,
        vault: Vault.example
    )
    .environmentObject(HomeViewModel())
}
