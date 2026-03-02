//
//  DeeplinkRouterModifier.swift
//  VultisigApp
//

import SwiftUI
import SwiftData
import WalletCore

struct DeeplinkRouterModifier: ViewModifier {
    @Binding var vaultRoute: VaultMainRoute?
    @Binding var showScanner: Bool
    @Binding var showVaultSelector: Bool
    @Binding var deeplinkError: Error?
    let sendTx: SendTransaction
    let vaults: [Vault]

    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var appViewModel: AppViewModel
    @EnvironmentObject var vultExtensionViewModel: VultExtensionViewModel
    @Environment(\.openURL) var openURL
    @Environment(\.router) var router

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ProcessDeeplink"))) { _ in
                handleDeeplinkNotification()
            }
            .onChange(of: deeplinkViewModel.type) { _, newValue in
                if newValue != nil {
                    presetValuesForDeeplink()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeeplinkVaultSelection"))) { notification in
                if let vault = notification.object as? Vault {
                    handleVaultSelection(vault: vault)
                }
            }
    }

    private func handleVaultSelection(vault: Vault) {
        if deeplinkViewModel.pendingSendDeeplink {
            let isAddressOnly = deeplinkViewModel.address != nil && deeplinkViewModel.assetChain == nil && deeplinkViewModel.assetTicker == nil

            if isAddressOnly, let address = deeplinkViewModel.address {
                processAddressOnlyDeeplink(address: address, vault: vault)
            } else {
                handleSendDeeplinkAfterVaultSelection(vault: vault)
            }
        } else if deeplinkViewModel.pendingConnectDeeplink {
            handleConnectDeeplinkAfterVaultSelection(vault: vault)
        }
    }

    private func handleDeeplinkNotification() {
        if showScanner {
            showScanner = false
            // Run presetValuesForDeeplink immediately without delay
            presetValuesForDeeplink()
        } else {
            presetValuesForDeeplink()
        }
    }

    func presetValuesForDeeplink() {
        if vultExtensionViewModel.documentData != nil {
            navigateToImportBackup()
        }

        guard let type = deeplinkViewModel.type else {
            return
        }

        deeplinkViewModel.type = nil

        switch type {
        case .NewVault:
            moveToCreateVaultView()
            deeplinkViewModel.tssType = nil
            deeplinkViewModel.jsonData = nil
        case .SignTransaction:
            moveToVaultsView()
        case .Send:
            handleSendDeeplink()
        case .ConnectDapp:
            handleConnectDeeplink()
        case .SignMessage:
            handleSignMessageDeeplink()
        case .Unknown:
            handleAddressOnlyDeeplink()
        }
    }

    private func handleSendDeeplink() {
        guard deeplinkViewModel.assetChain != nil || deeplinkViewModel.assetTicker != nil || deeplinkViewModel.address != nil else {
            return
        }

        guard !vaults.isEmpty else {
            // Re-check after a brief moment if vaults are not loaded yet
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !vaults.isEmpty {
                    handleSendDeeplink()
                }
            }
            return
        }

        if deeplinkViewModel.isInternalDeeplink, let selectedVault = appViewModel.selectedVault {
            closeScannerIfNeeded {
                self.handleSendDeeplinkAfterVaultSelection(vault: selectedVault)
            }
            return
        }

        if vaults.count == 1, let singleVault = vaults.first {
            closeScannerIfNeeded {
                self.handleSendDeeplinkAfterVaultSelection(vault: singleVault)
            }
            return
        }

        closeScannerIfNeeded {
            self.deeplinkViewModel.pendingSendDeeplink = true
            self.showVaultSelector = true
        }
    }

    private func handleConnectDeeplink() {
        guard deeplinkViewModel.dappUrl != nil, deeplinkViewModel.callbackUrl != nil else {
            return
        }

        guard !vaults.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !vaults.isEmpty {
                    handleConnectDeeplink()
                }
            }
            return
        }

        if vaults.count == 1, let singleVault = vaults.first {
            closeScannerIfNeeded {
                self.handleConnectDeeplinkAfterVaultSelection(vault: singleVault)
            }
            return
        }

        closeScannerIfNeeded {
            self.deeplinkViewModel.pendingConnectDeeplink = true
            self.showVaultSelector = true
        }
    }

    private func handleSignMessageDeeplink() {
        let resolvedVault = deeplinkViewModel.selectedVault ?? appViewModel.selectedVault ?? (vaults.count == 1 ? vaults.first : nil)

        guard let vault = resolvedVault else {
            deeplinkError = DeeplinkError.unrelatedQRCode
            deeplinkViewModel.resetData()
            return
        }

        guard let jsonDataString = deeplinkViewModel.jsonData,
              let data = jsonDataString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? String,
              let chain = json["chain"] as? String else {
            deeplinkError = DeeplinkError.unrelatedQRCode
            deeplinkViewModel.resetData()
            return
        }

        guard vault.coins.first(where: { $0.chain.name.caseInsensitiveCompare(chain) == .orderedSame }) != nil else {
            deeplinkError = DeeplinkError.unrelatedQRCode
            deeplinkViewModel.resetData()
            return
        }
        
        let method = json["method"] as? String ?? "sign_message"
        let callbackUrl = json["callbackUrl"] as? String

        appViewModel.set(selectedVault: vault, restartNavigation: false)
        deeplinkViewModel.resetData()

        vaultRoute = .mainAction(.signMessage(method: method, message: message, chain: chain, callbackUrl: callbackUrl))
    }

    func handleSendDeeplinkAfterVaultSelection(vault: Vault) {
        deeplinkViewModel.pendingSendDeeplink = false
        appViewModel.set(selectedVault: vault, restartNavigation: false)

        let coin = deeplinkViewModel.findCoin(in: vault)

        if coin == nil && deeplinkViewModel.assetChain != nil {
            let chainName = deeplinkViewModel.assetChain?.capitalized ?? "Unknown"
            deeplinkError = DeeplinkError.chainNotAdded(chainName: chainName)
            deeplinkViewModel.resetData()
            return
        }

        let savedAddress = deeplinkViewModel.address
        let savedAmount = deeplinkViewModel.sendAmount
        let savedMemo = deeplinkViewModel.sendMemo

        let coinToUse: Coin?
        if let coin = coin {
            coinToUse = coin
            sendTx.reset(coin: coin)
        } else if let defaultCoin = vault.coins.first {
            coinToUse = defaultCoin
            sendTx.reset(coin: defaultCoin)
        } else {
            coinToUse = nil
        }

        if let address = savedAddress {
            sendTx.toAddress = address
        }
        if let amount = savedAmount {
            sendTx.amount = amount
        }
        if let memo = savedMemo {
            sendTx.memo = memo
        }

        vaultRoute = .mainAction(.send(coin: coinToUse, hasPreselectedCoin: coinToUse != nil))
    }

    func handleConnectDeeplinkAfterVaultSelection(vault: Vault) {
        deeplinkViewModel.pendingConnectDeeplink = false
        appViewModel.set(selectedVault: vault, restartNavigation: false)

        guard let chainName = deeplinkViewModel.assetChain else {
            deeplinkError = DeeplinkError.chainNotAdded(chainName: "")
            deeplinkViewModel.resetData()
            return
        }

        guard let coin = vault.coins.first(where: { $0.chain.name.caseInsensitiveCompare(chainName) == .orderedSame }) else {
            deeplinkError = DeeplinkError.chainNotAdded(chainName: chainName.capitalized)
            deeplinkViewModel.resetData()
            return
        }
        
        guard let callbackUrl = deeplinkViewModel.callbackUrl else {
            deeplinkViewModel.resetData()
            return
        }

        let address = coin.address
        let vaultPubKey = vault.pubKeyECDSA
        deeplinkViewModel.resetData()

        guard var components = URLComponents(string: callbackUrl) else { return }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "address", value: address))
        queryItems.append(URLQueryItem(name: "vault", value: vaultPubKey))
        components.queryItems = queryItems
        
        if let finalUrl = components.url {
            openURL(finalUrl)
        }
    }

    private func handleAddressOnlyDeeplink() {
        guard let address = deeplinkViewModel.address, !address.isEmpty else {
            return
        }

        if deeplinkViewModel.isInternalDeeplink, let selectedVault = appViewModel.selectedVault {
            closeScannerIfNeeded {
                self.processAddressOnlyDeeplink(address: address, vault: selectedVault)
            }
            return
        }

        if vaults.count == 1, let singleVault = vaults.first {
            closeScannerIfNeeded {
                self.processAddressOnlyDeeplink(address: address, vault: singleVault)
            }
            return
        }

        deeplinkViewModel.pendingSendDeeplink = true
        closeScannerIfNeeded {
            self.showVaultSelector = true
        }
    }

    func processAddressOnlyDeeplink(address: String, vault: Vault) {
        appViewModel.set(selectedVault: vault, restartNavigation: false)

        var coinToUse: Coin?
        var chainToUse: Chain?
        for chain in Chain.allCases {
            if chain == .mayaChain {
                if AnyAddress.isValidBech32(string: address, coin: .thorchain, hrp: "maya") {
                    chainToUse = chain
                    break
                }
            } else {
                let isValid = chain.coinType.validate(address: address)
                if isValid {
                    chainToUse = chain
                    break
                }
            }
        }

        if let chainToUse {
            coinToUse = vault.coins.first { $0.chain == chainToUse && $0.isNativeToken }
        } else if address.lowercased().contains("maya") {
            chainToUse = .mayaChain
            coinToUse = vault.coins.first(where: { $0.chain == .mayaChain && $0.isNativeToken })
        }

        if chainToUse == nil {
            deeplinkError = DeeplinkError.unrelatedQRCode
            deeplinkViewModel.resetData()
            return
        }

        if coinToUse == nil {
            let chainName = chainToUse?.name ?? "Unknown"
            deeplinkError = DeeplinkError.chainNotAdded(chainName: chainName)
            deeplinkViewModel.resetData()
            return
        }

        if let coin = coinToUse {
            sendTx.reset(coin: coin)
        }

        sendTx.toAddress = address
        deeplinkViewModel.address = address

        self.vaultRoute = .mainAction(.send(coin: coinToUse, hasPreselectedCoin: coinToUse != nil))
    }

    private func closeScannerIfNeeded(completion: @escaping () -> Void) {
        if showScanner {
            showScanner = false
            completion()
        } else {
            completion()
        }
    }

    private func moveToVaultsView() {
        guard let vault = deeplinkViewModel.selectedVault else {
            return
        }

        appViewModel.set(selectedVault: vault, restartNavigation: false)
        showVaultSelector = false
        navigateToJoinKeysign()
    }

    private func moveToCreateVaultView() {
        guard let selectedVault = appViewModel.selectedVault else { return }
        showVaultSelector = false
        navigateToJoinKeygen(selectedVault: selectedVault)
    }

    private func navigateToJoinKeygen(selectedVault: Vault) {
        router.navigate(to: OnboardingRoute.joinKeygen(
            vault: Vault(name: "Main Vault"),
            selectedVault: selectedVault
        ))
    }

    private func navigateToJoinKeysign() {
        guard let vault = appViewModel.selectedVault else { return }
        router.navigate(to: KeygenRoute.joinKeysign(vault: vault))
    }

    private func navigateToImportBackup() {
        router.navigate(to: OnboardingRoute.importVaultShare)
    }
}

extension View {
    func withDeeplinkRouter(
        vaultRoute: Binding<VaultMainRoute?>,
        showScanner: Binding<Bool>,
        showVaultSelector: Binding<Bool>,
        deeplinkError: Binding<Error?>,
        sendTx: SendTransaction,
        vaults: [Vault]
    ) -> some View {
        modifier(DeeplinkRouterModifier(
            vaultRoute: vaultRoute,
            showScanner: showScanner,
            showVaultSelector: showVaultSelector,
            deeplinkError: deeplinkError,
            sendTx: sendTx,
            vaults: vaults
        ))
    }
}
