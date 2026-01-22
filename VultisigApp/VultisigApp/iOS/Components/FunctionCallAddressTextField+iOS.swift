//
//  FunctionCallAddressTextField+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

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
                AddressBookView(returnAddress: Binding<String>(
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
