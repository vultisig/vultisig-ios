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
            router.navigate(to: OnboardingRoute.devicesSelection(tssType: .Keygen, keyImportInput: nil))
        }
        .opacity(showNewVaultButton ? 1 : 0)
        .offset(y: showNewVaultButton ? 0 : 20)
        .scaleEffect(showNewVaultButton ? 1 : 0.8)
        .animation(.spring(duration: 0.3), value: showNewVaultButton)
    }

    var importVaultButton: some View {
        PrimaryButton(
            title: "import",
            leadingIcon: "arrow-down-circle",
            trailingView: { newTag },
            type: .secondary,
            action: { showImportSelectionSheet = true }
        )
    }

    private var newTag: some View {
        HStack(spacing: 2) {
            Icon(
                named: "stars",
                color: Theme.colors.alertWarning,
                size: canFitFullNewTag ? 8 : 12
            )
            Text("new")
                .foregroundStyle(Theme.colors.alertWarning)
                .font(FontStyle.brockmanMedium.size(8))
                .showIf(canFitFullNewTag)
        }
    }

    private var canFitFullNewTag: Bool {
        #if os(iOS)
        let titleText = "import".localized
        let tagText = "new".localized

        let titleFont = FontStyle.brockmanSemibold.uiFont(16)
        let tagFont = FontStyle.brockmanMedium.uiFont(8)

        let titleWidth = (titleText as NSString).size(withAttributes: [.font: titleFont]).width
        let tagTextWidth = (tagText as NSString).size(withAttributes: [.font: tagFont]).width

        // Button width: each button gets half of (screen - 2×24 horizontal padding - 8 HStack spacing)
        let buttonWidth = CGFloat((Float(UIScreen.main.bounds.width) - 48 - 8) / 2)

        // Content inside PrimaryButtonView HStack(spacing: 8):
        // leadingIcon(15) + title + tagIcon(8) + tagSpacing(2) + tagText + 3×spacing(8)
        let contentWidth: CGFloat = 15 + titleWidth * 1.5 + 8 + 2 + tagTextWidth + 24

        return contentWidth <= buttonWidth
        #else
        return true
        #endif
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
