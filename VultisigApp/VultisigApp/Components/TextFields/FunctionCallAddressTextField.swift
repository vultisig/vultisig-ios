//
//  FunctionCallAddressTextField.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 14/05/24.
//
import SwiftUI
import Foundation
import OSLog
import UniformTypeIdentifiers
import WalletCore

struct FunctionCallAddressTextField<MemoType: FunctionCallAddressable>: View {

    @ObservedObject var memo: MemoType
    var addressKey: String
    var isOptional: Bool = false

    @Binding var isAddressValid: Bool
    @State var showScanner = false
    @State var showImagePicker = false
    @State var isUploading: Bool = false
    @State var showAddressBookSheet: Bool = false

    @State var chain: Chain? = nil

#if os(iOS)
    @State var selectedImage: UIImage?
#elseif os(macOS)
    @State var selectedImage: NSImage?
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(NSLocalizedString("nodeAddressLabel", comment: "Node Address placeholder") + optionalMessage)
                    .font(Theme.fonts.bodySMedium)
                    .foregroundColor(Theme.colors.textPrimary)

                if !isAddressValid {
                    Text("*")
                        .font(Theme.fonts.bodySMedium)
                        .foregroundColor(.red)
                }
            }

            container
        }
        .onChange(of: memo.addressFields[addressKey]) { _, newValue in
            validateAddress(newValue ?? "")
        }
    }

    var content: some View {
        field
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
            Image(systemName: "doc.on.clipboard")
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
                .frame(width: 40, height: 40)
        }
    }

    var scanButton: some View {
        Button {
            showScanner.toggle()
        } label: {
            Image(systemName: "camera")
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
                .frame(width: 40, height: 40)
        }
    }

    var fileButton: some View {
        Button {
            showImagePicker.toggle()
        } label: {
            Image(systemName: "photo.badge.plus")
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
                .frame(width: 40, height: 40)
        }
    }

    var addressBookButton: some View {
        Button {
            showAddressBookSheet.toggle()
        } label: {
            Image(systemName: "text.book.closed")
                .font(Theme.fonts.bodyMRegular)
                .foregroundColor(Theme.colors.textPrimary)
                .frame(width: 40, height: 40)
        }
    }

    var optionalMessage: String {
        if isOptional {
            return " " + NSLocalizedString("optional", comment: "Optional field indicator")
        }
        return .empty
    }

    func validateAddress(_ newValue: String) {

        if isOptional, newValue.isEmpty {
            isAddressValid = true
            return
        }

        isAddressValid = AddressService.validateAddress(address: newValue, chain: .thorChain) ||
        AddressService.validateAddress(address: newValue, chain: .mayaChain) ||
        AddressService.validateAddress(address: newValue, chain: .ton)

        if let chain = chain, chain.chainType == .Cosmos {
            isAddressValid = AddressService.validateAddress(address: newValue, chain: chain)
        }
    }
}

#if os(iOS)
import SwiftUI
import CodeScanner

extension FunctionCallAddressTextField {
    var container: some View {
        content
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(10)
            .crossPlatformSheet(isPresented: $showScanner) {
                codeScanner
            }
            .sheet(isPresented: $showImagePicker, onDismiss: processImage) {
                ImagePicker(selectedImage: $selectedImage)
            }
            .crossPlatformSheet(isPresented: $showAddressBookSheet) {
                AddressBookScreen(returnAddress: Binding<String>(
                    get: { memo.addressFields[addressKey] ?? "" },
                    set: { newValue in
                        memo.addressFields[addressKey] = newValue
                        DebounceHelper.shared.debounce {
                            validateAddress(newValue)
                        }
                    }
                ))
            }
    }

    var field: some View {
        HStack(spacing: 0) {
            TextField(addressKey.toFormattedTitleCase(), text: Binding<String>(
                get: { memo.addressFields[addressKey] ?? "" },
                set: { newValue in
                    memo.addressFields[addressKey] = newValue
                    DebounceHelper.shared.debounce {
                        validateAddress(newValue)
                    }
                }
            ))
            .foregroundColor(Theme.colors.textPrimary)
            .submitLabel(.next)
            .disableAutocorrection(true)
            .borderlessTextFieldStyle()
            .maxLength(Binding<String>(
                get: { memo.addressFields[addressKey] ?? "" },
                set: { newValue in
                    memo.addressFields[addressKey] = newValue
                    DebounceHelper.shared.debounce {
                        validateAddress(newValue)
                    }
                }
            ))
            .textInputAutocapitalization(.never)
            .keyboardType(.default)
            .textContentType(.oneTimeCode)

            pasteButton
            fileButton
            addressBookButton
        }
        .padding(.horizontal, 12)
    }

    var codeScanner: some View {
        AddressQRCodeScannerView(
            showScanner: $showScanner,
            onAddress: { handleScan(result: $0) }
        )
    }

    private func binding() -> Binding<String> {
        return Binding(
            get: { self.memo.addressFields[addressKey, default: ""] },
            set: { self.memo.addressFields[addressKey] = $0 }
        )
    }

    func processImage() {
        guard let selectedImage = selectedImage else { return }
        handleImageQrCode(image: selectedImage)
    }

    private func handleScan(result: String) {
        memo.addressFields[addressKey] = result
        validateAddress(memo.addressFields[addressKey] ?? "")
        showScanner = false
    }

    private func handleImageQrCode(image: UIImage) {
        let qrCodeFromImage = Utils.handleQrCodeFromImage(image: image)
        let address = String(data: qrCodeFromImage, encoding: .utf8) ?? ""
        memo.addressFields[addressKey] = address
        validateAddress(memo.addressFields[addressKey] ?? "")
    }

    func pasteAddress() {
        if let clipboardContent = UIPasteboard.general.string {
            memo.addressFields[addressKey] = clipboardContent
            DebounceHelper.shared.debounce {
                validateAddress(clipboardContent)
            }
        }
    }
}
#endif

#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

extension FunctionCallAddressTextField {
    var container: some View {
        content
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.colors.bgSurface1)
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
            .crossPlatformSheet(isPresented: $showAddressBookSheet) {
                AddressBookScreen(returnAddress: Binding<String>(
                    get: { memo.addressFields[addressKey] ?? "" },
                    set: { newValue in
                        memo.addressFields[addressKey] = newValue
                        DebounceHelper.shared.debounce {
                            validateAddress(newValue)
                        }
                    }
                ))
            }
    }

    var field: some View {
        HStack(spacing: 0) {
            TextField(addressKey.toFormattedTitleCase(), text: Binding<String>(
                get: { memo.addressFields[addressKey] ?? "" },
                set: { newValue in
                    memo.addressFields[addressKey] = newValue
                    DebounceHelper.shared.debounce {
                        validateAddress(newValue)
                    }
                }
            ))
            .foregroundColor(Theme.colors.textPrimary)
            .submitLabel(.next)
            .disableAutocorrection(true)
            .borderlessTextFieldStyle()
            .maxLength(Binding<String>(
                get: { memo.addressFields[addressKey] ?? "" },
                set: { newValue in
                    memo.addressFields[addressKey] = newValue
                    DebounceHelper.shared.debounce {
                        validateAddress(newValue)
                    }
                }
            ))

            pasteButton
            fileButton
            addressBookButton
        }
        .padding(.horizontal, 12)
    }

    private func handleImageQrCode(data: Data) {
        let (address, amount, _) = Utils.parseCryptoURI(String(data: data, encoding: .utf8) ?? .empty)
        memo.addressFields[addressKey] = address
        memo.addressFields["amount"] = amount
        validateAddress(address)
    }

    func pasteAddress() {
        let pasteboard = NSPasteboard.general
        if let clipboardContent = pasteboard.string(forType: .string) {
            memo.addressFields[addressKey] = clipboardContent
            validateAddress(memo.addressFields[addressKey] ?? "")
        }
    }
}
#endif
