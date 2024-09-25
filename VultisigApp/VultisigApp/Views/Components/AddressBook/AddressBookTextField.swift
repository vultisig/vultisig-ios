//
//  AddressBookTextField.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-11.
//

import SwiftUI
import UniformTypeIdentifiers

struct AddressBookTextField: View {
    let title: String
    @Binding var text: String
    var showActions = false
    
    @State var showScanner = false
    @State var showImagePicker = false
    
    @State var isUploading: Bool = false
    
#if os(iOS)
    @State var selectedImage: UIImage?
#elseif os(macOS)
    @State var selectedImage: NSImage?
#endif
    
    var body: some View {
        content
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
    
    var placeholder: some View {
        Text(NSLocalizedString("typeHere", comment: ""))
            .foregroundColor(Color.neutral0)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    
    func handleImageQrCode(data: Data) {
        text = String(data: data, encoding: .utf8) ?? ""
        showImagePicker = false
    }
}

#Preview {
    ZStack {
        Background()
        AddressBookTextField(title: "title", text: .constant(""))
    }
}
