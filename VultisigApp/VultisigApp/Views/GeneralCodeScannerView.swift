//
//  GeneralCodeScannerView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-05-30.
//

import SwiftUI
import CodeScanner
import SwiftData

struct GeneralCodeScannerView: View {
    let isForKeysign: Bool
    @Binding var isGalleryPresented: Bool
    @Binding var showScanner: Bool
    let handleScan: @MainActor (URL?) -> ()
    
    @State var shouldJoinKeygen = false
    @State var shouldKeysignTransaction = false
    
    @Query var vaults: [Vault]
    
    @EnvironmentObject var deeplinkViewModel: DeeplinkViewModel
    @EnvironmentObject var viewModel: HomeViewModel
    
    var body: some View {
        ZStack(alignment: .bottom) {
            CodeScannerView(codeTypes: [.qr], isGalleryPresented: $isGalleryPresented, completion: handleScan)
            galleryButton
        }
    }
    
    var galleryButton: some View {
        Button {
            isGalleryPresented.toggle()
        } label: {
            OpenGalleryButton()
        }
        .padding(.bottom, 50)
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            guard let url = URL(string: result.string) else {
                return
            }
            deeplinkViewModel.extractParameters(url, vaults: vaults)
            presetValuesForDeeplink(url)
        case .failure(_):
            showScanner = false
            return
        }
    }
    
    private func presetValuesForDeeplink(_ url: URL) {
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            handleScan(url)
            showScanner = false
//        }
        
//        switch type {
//        case .NewVault:
//            moveToCreateVaultView()
//        case .SignTransaction:
//            moveToVaultsView()
//        case .Unknown:
//            return
//        }
    }
    
    private func moveToCreateVaultView() {
        shouldJoinKeygen = true
    }
    
    private func moveToVaultsView() {
        guard let vault = deeplinkViewModel.selectedVault else {
            return
        }
        
        viewModel.setSelectedVault(vault)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            shouldKeysignTransaction = true
        }
    }
}

//#Preview {
//    func example() {}
//    
//    GeneralCodeScannerView(isForKeysign: true, isGalleryPresented: .constant(false), showScanner: .constant(true), handleScan: example, url: URL(string: "")!)
//        .environmentObject(DeeplinkViewModel())
//}
