//
//  GeneralCodeScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-30.
//
#if os(iOS)
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CodeScanner
import AVFoundation

struct GeneralCodeScannerView: View {
    @Binding var showSheet: Bool
    @Binding var shouldJoinKeygen: Bool
    @Binding var shouldKeysignTransaction: Bool
    @Binding var shouldSendCrypto: Bool
    @Binding var selectedChain: Chain?
    
    let sendTX: SendTransaction
    
    @State var isGalleryPresented = false
    @State var isFilePresented = false
    
    @Query var vaults: [Vault]
    
    @State var showAlert: Bool = false
    @State var newCoinMeta: CoinMeta? = nil
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var vaultDetailViewModel: VaultDetailViewModel
    @EnvironmentObject var coinSelectionViewModel: CoinSelectionViewModel
    @EnvironmentObject var homeViewModel: HomeViewModel
    
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var body: some View {
        QRCodeScannerView(
            showScanner: $showSheet
        ) { result in
            guard let url = URL(string: result) else {
                return
            }
            deeplinkViewModel.extractParameters(url, vaults: vaults)
            presetValuesForDeeplink()
        } handleScan: { result in
            handleScan(result: result)
        }
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            guard let url = URL(string: result.string) else {
                return
            }
            deeplinkViewModel.extractParameters(url, vaults: vaults)
            presetValuesForDeeplink()
        case .failure(_):
            return
        }
    }
    
    private func presetValuesForDeeplink() {
        shouldJoinKeygen = false
        shouldKeysignTransaction = false
        
        guard let type = deeplinkViewModel.type else {
            return
        }
        deeplinkViewModel.type = nil
        
        switch type {
        case .NewVault:
            moveToCreateVaultView()
        case .SignTransaction:
            moveToVaultsView()
        case .Unknown:
            moveToSendView()
        }
    }
    
    private func moveToCreateVaultView() {
        shouldSendCrypto = false
        showSheet = false
        shouldJoinKeygen = true
    }
    
    private func moveToVaultsView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showSheet = false
            shouldSendCrypto = false
            shouldKeysignTransaction = true
        }
    }
    
    private func moveToSendView() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shouldJoinKeygen = false
            showSheet = false
            checkForAddress()
        }
    }
    
    private func checkForAddress() {
        let address = deeplinkViewModel.address ?? ""
        sendTX.toAddress = address
        
        for asset in vaultDetailViewModel.groups {
            if checkForMAYAChain(asset: asset, address: address) {
                return
            }
            
            let isValid = asset.chain.coinType.validate(address: address)
            
            if isValid {
                selectedChain = asset.chain
                shouldSendCrypto = true
                
                return
            }
        }
        
        checkForRemainingChains(address)
    }
    
    private func checkForMAYAChain(asset: GroupedChain, address: String) -> Bool {
        if asset.name.lowercased().contains("maya") && address.lowercased().contains("maya") {
            selectedChain = asset.chain
            shouldSendCrypto = true
            return true
        } else {
            return false
        }
    }
    
    private func checkForRemainingChains(_ address: String) {
        showSheet = true
        
        let chains = coinSelectionViewModel.groupedAssets.values.flatMap { $0 }
        
        for asset in chains.sorted(by: {
            $0.chain.name < $1.chain.name
        }) {
            let isValid = asset.coinType.validate(address: address)
            
            if isValid {
                newCoinMeta = asset
                showAlert = true
                return
            }
        }
    }
    
    private func handleCancel() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            showSheet = false
            shouldSendCrypto = true
        }
    }
    
    private func addNewChain() {
        guard let chain = newCoinMeta else {
            return
        }
        
        selectedChain = chain.chain
        saveAssets(chain)
    }
    
    private func saveAssets(_ chain: CoinMeta) {
        var selection = coinSelectionViewModel.selection
        selection.insert(chain)
        
        guard let vault = homeViewModel.selectedVault else {
            return
        }
        
        Task{
            await CoinService.saveAssets(for: vault, selection: selection)
            
            handleCancel()
        }
    }
}

#Preview {
    GeneralCodeScannerView(
        showSheet: .constant(true),
        shouldJoinKeygen: .constant(true),
        shouldKeysignTransaction: .constant(true), 
        shouldSendCrypto: .constant(true),
        selectedChain: .constant(nil), 
        sendTX: SendTransaction()
    )
    .environmentObject(DeeplinkViewModel())
    .environmentObject(HomeViewModel())
    .environmentObject(VaultDetailViewModel())
    .environmentObject(CoinSelectionViewModel())
    .environmentObject(HomeViewModel())
}
#endif
