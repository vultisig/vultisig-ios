//
//  FunctionCallAddressTextField+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-24.
//

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
