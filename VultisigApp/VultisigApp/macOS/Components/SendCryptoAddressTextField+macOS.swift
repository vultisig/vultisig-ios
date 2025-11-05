//
//  SendCryptoAddressTextField+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

extension SendCryptoAddressTextField {
    var container: some View {
        content
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.colors.bgSecondary)
            .cornerRadius(10)
            .fileImporter(
                isPresented: $showImagePicker,
                allowedContentTypes: [UTType.image],
                allowsMultipleSelection: false
            ) { result in
                do {
                    let qrCode = try Utils.handleQrCodeFromImage(result: result)
                    handleImageQrCode(data: qrCode)
                } catch {
                    print(error)
                }
            }
            .onDrop(of: [.image], isTargeted: $isUploading) { providers -> Bool in
                OnDropQRUtils.handleOnDrop(providers: providers, handleImageQrCode: handleImageQrCode)
            }
            .navigationDestination(isPresented: $showCameraScanView) {
                MacAddressScannerView(
                    tx: tx,
                    sendCryptoViewModel: sendCryptoViewModel,
                    showCameraScanView: $showCameraScanView,
                    selectedVault: vault,
                    sendDetailsViewModel: sendDetailsViewModel
                )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(sendCryptoViewModel.showAddressAlert ? Theme.colors.alertWarning : Theme.colors.bgTertiary, lineWidth: 1)
            )
            .padding(1)
    }
    
    var field: some View {
        HStack(spacing: 0) {
            TextField(NSLocalizedString("enterAddressHere", comment: "").capitalized, text: Binding<String>(
                get: { tx.toAddress },
                set: { newValue in
                    tx.toAddress = newValue
                    handleAddressChange(newValue)
                }
            ))
            .onChange(of: tx.toAddress) { oldValue, newValue in
                Task {
                    await sendCryptoViewModel.loadGasInfoForSending(tx: tx)
                }
            }
            .foregroundColor(Theme.colors.textPrimary)
            .font(Theme.fonts.bodySMedium)
            .submitLabel(.next)
            .disableAutocorrection(true)
            .borderlessTextFieldStyle()
            .maxLength(Binding<String>(
                get: { tx.toAddress },
                set: { newValue in
                    tx.toAddress = newValue
                    handleAddressChange(newValue)
                }
            ))
        }
        .padding(.horizontal, 12)
    }
    var scanButton: some View {
        Button {
            showCameraScanView.toggle()
        } label: {
            getButton("camera")
        }
    }
    
    func pasteAddress() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string) {
            tx.toAddress = clipboardContent
            handleAddressChange(clipboardContent)
        }
    }
    
    private func handleAddressChange(_ address: String) {
        // Attempt to detect and switch chain if address belongs to different chain
        if let viewModel = sendDetailsViewModel, let vault = vault, !address.isEmpty {
            let detectedCoin = viewModel.detectAndSwitchChain(from: address, vault: vault, currentChain: tx.coin.chain, tx: tx)
            
            if detectedCoin != nil {
                // Chain was detected and switched
                // Clear previous error first
                sendCryptoViewModel.showAddressAlert = false
                sendCryptoViewModel.errorMessage = ""
                sendCryptoViewModel.isValidAddress = true
                
                // Mark address as done and move to amount
                if let detailsVM = sendDetailsViewModel {
                    detailsVM.addressSetupDone = true
                    detailsVM.onSelect(tab: .amount)
                }
            } else {
                // No chain change needed, validate with debounce
                DebounceHelper.shared.debounce {
                    self.validateAddress(address)
                }
            }
        } else {
            DebounceHelper.shared.debounce {
                validateAddress(address)
            }
        }
    }
    
    private func handleImageQrCode(data: Data) {
        let (address, amount, message) = Utils.parseCryptoURI(String(data: data, encoding: .utf8) ?? .empty)
        
        tx.toAddress = address
        tx.amount = amount
        tx.memo = message
        
        // Use the same handler
        handleAddressChange(address)
        
        if !amount.isEmpty {
            sendCryptoViewModel.convertToFiat(newValue: amount, tx: tx)
        }
        
    }
}
#endif
