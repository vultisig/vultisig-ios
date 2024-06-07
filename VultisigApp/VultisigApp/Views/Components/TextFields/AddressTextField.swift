import SwiftUI
import OSLog
import CodeScanner
import UniformTypeIdentifiers

struct AddressTextField: View {
    @Binding var contractAddress: String
    var validateAddress: (String) -> Void
    
    @State private var showScanner = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    
    var body: some View {
        ZStack(alignment: .trailing) {
            if contractAddress.isEmpty {
                placeholder
            }
            
            field
        }
        .font(.body12Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
        .sheet(isPresented: $showScanner) {
            codeScanner
        }
        .sheet(isPresented: $showImagePicker, onDismiss: processImage) {
            ImagePicker(selectedImage: $selectedImage)
        }
    }
    
    var placeholder: some View {
        Text(NSLocalizedString("enterContractAddress", comment: "").toFormattedTitleCase())
            .foregroundColor(Color.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var field: some View {
        HStack(spacing: 0) {
            TextField(NSLocalizedString("enterContractAddress", comment: "").capitalized, text: $contractAddress)
                .foregroundColor(.neutral0)
                .submitLabel(.next)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(.default)
                .textContentType(.oneTimeCode)
                .onChange(of: contractAddress, perform: validateAddress)
            
            pasteButton
            scanButton
            fileButton
        }
    }
    
    var codeScanner: some View {
        QRCodeScannerView(showScanner: $showScanner, handleScan: handleScan)
    }
    
    var pasteButton: some View {
        Button {
            pasteAddress()
        } label: {
            Image(systemName: "doc.on.clipboard")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    var scanButton: some View {
        Button {
            showScanner.toggle()
        } label: {
            Image(systemName: "camera")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    var fileButton: some View {
        Button {
            showImagePicker.toggle()
        } label: {
            Image(systemName: "photo.badge.plus")
                .font(.body16Menlo)
                .foregroundColor(.neutral0)
                .frame(width: 40, height: 40)
        }
    }
    
    private func processImage() {
        guard let selectedImage = selectedImage else { return }
        handleImageQrCode(image: selectedImage)
    }
    
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            let qrCodeResult = result.string
            contractAddress = qrCodeResult
            validateAddress(qrCodeResult)
            showScanner = false
        case .failure(let err):
            // Handle the error appropriately
            print("Failed to scan QR code: \(err.localizedDescription)")
        }
    }
    
    private func pasteAddress() {
        if let clipboardContent = UIPasteboard.general.string {
            contractAddress = clipboardContent
            validateAddress(clipboardContent)
        }
    }
    
    private func handleImageQrCode(image: UIImage) {
        if let qrCodeFromImage = Utils.handleQrCodeFromImage(image: image) as Data?,
           let qrCodeString = String(data: qrCodeFromImage, encoding: .utf8) {
            contractAddress = qrCodeString
            validateAddress(qrCodeString)
        }
    }
}
