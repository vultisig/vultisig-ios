import SwiftUI
import OSLog
import UniformTypeIdentifiers

#if os(iOS)
import CodeScanner
#endif

struct AddressTextField: View {
    @Binding var contractAddress: String
    var validateAddress: (String) -> Void
    
    @State private var showScanner = false
    @State private var showImagePicker = false
    
#if os(iOS)
    @State private var selectedImage: UIImage?
#elseif os(macOS)
    @State private var selectedImage: NSImage?
#endif
    
    var body: some View {
        ZStack(alignment: .trailing) {
            
            field
        }
        .font(.body12Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
#if os(iOS)
        .sheet(isPresented: $showScanner) {
            codeScanner
        }
        .sheet(isPresented: $showImagePicker, onDismiss: processImage) {
            ImagePicker(selectedImage: $selectedImage)
        }
#endif
    }
    
    var placeholder: some View {
        Text(NSLocalizedString("enterContractAddress", comment: "").toFormattedTitleCase())
            .foregroundColor(Color.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var field: some View {
        HStack(spacing: 0) {
            TextField(NSLocalizedString("enterContractAddress", comment: "").toFormattedTitleCase(), text: $contractAddress)
                .foregroundColor(.neutral0)
                .submitLabel(.next)
                .disableAutocorrection(true)
                .textContentType(.oneTimeCode)
                .onChange(of: contractAddress){oldValue,newValue in
                    validateAddress(newValue)
                }
                .borderlessTextFieldStyle()
#if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.default)
#endif
            
            pasteButton
            scanButton
            fileButton
        }
    }
    
#if os(iOS)
    var codeScanner: some View {
        QRCodeScannerView(showScanner: $showScanner, handleScan: handleScan)
    }
#endif
    
    var pasteButton: some View {
        Button {
#if os(iOS)
            pasteAddress()
#endif
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
#if os(iOS)
        handleImageQrCode(image: selectedImage)
#endif
    }
    
#if os(iOS)
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
#endif
}
