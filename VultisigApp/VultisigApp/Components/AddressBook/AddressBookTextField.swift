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
    var isScrollable = false

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
            Theme.colors.bgButtonPrimary.opacity(0.2)
                .frame(height: 48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cornerRadius(10)

            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.colors.bgButtonPrimary, style: StrokeStyle(lineWidth: 1, dash: [10]))
                .padding(5)

            Text(NSLocalizedString("dropFileHere", comment: ""))
                .font(Theme.fonts.caption12)
                .foregroundColor(Theme.colors.textPrimary)
        }
    }

    var pasteButton: some View {
        Button {
            pasteAddress()
        } label: {
            Icon(named: "copy", color: Theme.colors.textPrimary, size: 20)
        }
    }

    var scanButton: some View {
        Button {
            showScanner.toggle()
        } label: {
            Icon(named: "camera", color: Theme.colors.textPrimary, size: 20)
        }
    }

    var fileButton: some View {
        Button {
            showImagePicker.toggle()
        } label: {
            Icon(named: "image-plus", color: Theme.colors.textPrimary, size: 20)
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
