//
//  AddressBookTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import CodeScanner
#endif

struct AddressBookTextField: View {
    let title: String
    @Binding var text: String
    var showActions = false
    
    @State var showScanner = false
    @State var showImagePicker = false
    
    @State var isUploading: Bool = false
    
#if os(iOS)
    @State var selectedImage: UIImage?  // Store the selected image
#elseif os(macOS)
    @State var selectedImage: NSImage?
#endif
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleContent
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
#if os(iOS)
        .sheet(isPresented: $showScanner) {
            codeScanner
        }
#endif
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
            handleOnDrop(providers: providers)
        }
    }
    
    var content: some View {
        textField
            .overlay {
                ZStack {
                    if isUploading {
                        overlay
                    }
                }
            }
    }
    
    var overlay: some View {
        ZStack {
            Color.turquoise600.opacity(0.2)
                .frame(height: 48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cornerRadius(10)
            
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 1, dash: [10]))
                .padding(5)
            
            Text(NSLocalizedString("dropFileHere", comment: ""))
                .font(.body12MontserratSemiBold)
                .foregroundColor(.neutral0)
        }
    }
    
    var titleContent: some View {
        Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(Color.neutral0)
            .font(.body14MontserratMedium)
    }
    
    var textField: some View {
        HStack {
            field
            
            if showActions {
                pasteButton
#if os(iOS)
                scanButton
#elseif os(macOS)
                fileButton
#endif
            }
        }
        .font(.body12Menlo)
        .foregroundColor(.neutral0)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background(Color.blue600)
        .cornerRadius(10)
        .colorScheme(.dark)
    }
    
    var placeholder: some View {
        Text(NSLocalizedString("typeHere", comment: ""))
            .foregroundColor(Color.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    var field: some View {
        HStack(spacing: 0) {
            TextField(NSLocalizedString("typeHere", comment: "").capitalized, text: $text)
            .foregroundColor(.neutral0)
            .submitLabel(.next)
            .disableAutocorrection(true)
            .borderlessTextFieldStyle()
#if os(iOS)
            .keyboardType(.default)
            .textInputAutocapitalization(.never)
            .textContentType(.oneTimeCode)
#endif
        }
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
    
#if os(iOS)
    var codeScanner: some View {
        QRCodeScannerView(showScanner: $showScanner, handleScan: handleScan)
    }
#endif
    
    private func pasteAddress() {
#if os(iOS)
        if let clipboardContent = UIPasteboard.general.string {
            text = clipboardContent
        }
#elseif os(macOS)
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string) {
            text = clipboardContent
        }
#endif
    }
    
#if os(iOS)
    private func handleScan(result: Result<ScanResult, ScanError>) {
        switch result {
        case .success(let result):
            text = result.string
            showScanner = false
        case .failure(let err):
            print("fail to scan QR code,error:\(err.localizedDescription)")
        }
    }
#endif
    
    private func handleImageQrCode(data: Data) {
        text = String(data: data, encoding: .utf8) ?? ""
        showImagePicker = false
    }
    
    private func handleOnDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.image") }) else {
            print("Invalid file type. Please drop an image.")
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, error in
            guard let data = data, let image = NSImage(data: data) else {
                print(error?.localizedDescription ?? "Failed to load image.")
                return
            }

            // Extract QR code data from the image
            if let qrData = extractQRCode(from: image) {
                handleImageQrCode(data: qrData)
            } else {
                print("No QR code detected in the image.")
            }
        }

        return true
    }

    private func extractQRCode(from nsImage: NSImage) -> Data? {
        guard let tiffData = nsImage.tiffRepresentation,
              let ciImage = CIImage(data: tiffData) else {
            return nil
        }

        let context = CIContext()
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])

        if let features = detector?.features(in: ciImage), !features.isEmpty {
            for feature in features {
                if let qrFeature = feature as? CIQRCodeFeature, let qrString = qrFeature.messageString {
                    return Data(qrString.utf8)
                }
            }
        }

        return nil
    }
}

#Preview {
    ZStack {
        Background()
        AddressBookTextField(title: "title", text: .constant(""))
    }
}
