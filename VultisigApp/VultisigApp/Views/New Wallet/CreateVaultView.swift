//
//  CreateVaultView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct CreateVaultView: View {
    @Environment(\.router) var router
    let selectedVault: Vault?
    var showBackButton = false

    @State var showNewVaultButton = false
    @State var showSeparator = false
    @State var showButtonStack = false
    @State var showSheet = false
    @State var shouldJoinKeygen = false
    @State var showImportSelectionSheet: Bool = false
    @State var navigateToScanQR = false
    @State var navigateToGeneralQRImport = false

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel

    init(selectedVault: Vault? = nil, showBackButton: Bool = false) {
        self.selectedVault = selectedVault
        self.showBackButton = showBackButton
    }

    var body: some View {
        main
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PrimaryBackgroundWithGradient())
        .navigationBarBackButtonHidden(showBackButton ? false : true)
        .onChange(of: navigateToScanQR) { _, shouldNavigate in
            guard shouldNavigate else { return }
            router.navigate(to: KeygenRoute.macScanner(
                type: .NewVault,
                sendTx: SendTransaction(),
                selectedVault: selectedVault
            ))
            navigateToScanQR = false
        }
        .onChange(of: navigateToGeneralQRImport) { _, shouldNavigate in
            guard shouldNavigate else { return }
            router.navigate(to: KeygenRoute.generalQRImport(
                type: .NewVault,
                selectedVault: nil,
                sendTx: nil
            ))
            navigateToGeneralQRImport = false
        }
        .crossPlatformSheet(isPresented: $showImportSelectionSheet) {
            ImportVaultSelectionSheet(isPresented: $showImportSelectionSheet) {
                showImportSelectionSheet = false
                router.navigate(to: OnboardingRoute.keyImportOnboarding)
            } onVaultShare: {
                showImportSelectionSheet = false
                router.navigate(to: OnboardingRoute.importVaultShare)
            }
        }
        .onLoad {
            setData()
        }
    }

    var headerMac: some View {
        CreateVaultHeader(showBackButton: showBackButton)
    }

    var view: some View {
        VStack(spacing: 0) {
            Spacer()
            VultisigLogoAnimation()
            Spacer()
            buttons
        }
    }

    var buttons: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                scanButton
                importVaultButton
            }
            .opacity(showButtonStack ? 1 : 0)
            .offset(y: showButtonStack ? 0 : 50)
            .scaleEffect(showButtonStack ? 1 : 0.8)
            .blur(radius: showButtonStack ? 0 : 10)
            .animation(.spring(duration: 0.3), value: showButtonStack)
            newVaultButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
    }

    var newVaultButton: some View {
        PrimaryButton(title: "getStarted") {
            if appViewModel.showOnboarding {
                router.navigate(to: OnboardingRoute.onboarding)
            } else {
                router.navigate(to: OnboardingRoute.devicesSelection(tssType: .Keygen, keyImportInput: nil))
            }
        }
        .opacity(showNewVaultButton ? 1 : 0)
        .offset(y: showNewVaultButton ? 0 : 20)
        .scaleEffect(showNewVaultButton ? 1 : 0.8)
        .animation(.spring(duration: 0.3), value: showNewVaultButton)
    }

    var importVaultButton: some View {
        ZStack(alignment: .center) {
            PrimaryButton(
                title: "import",
                leadingIcon: "arrow-down-circle",
                type: .secondary,
                reserveTrailingIconSpace: true
            ) {
                showImportSelectionSheet = true
            }
            newTag
                .offset(x: 48)
        }
    }

    private var newTag: some View {
        HStack(spacing: 2) {
            Icon(
                named: "stars",
                color: Theme.colors.alertWarning,
                size: 8
            )
            Text("new")
                .foregroundStyle(Theme.colors.alertWarning)
                .font(FontStyle.brockmanMedium.size(8))
        }
    }

    private func setData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showNewVaultButton = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showSeparator = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showButtonStack = true
        }
    }

    func createVault() -> Vault {
        let vaultName = Vault.getUniqueVaultName(modelContext: modelContext)
        return Vault(name: vaultName)
    }
}

#Preview {
    CreateVaultView(selectedVault: Vault.example)
        .environmentObject(AppViewModel())
        .environmentObject(DeeplinkViewModel())
}
