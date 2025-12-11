//
//  CircleDepositView.swift
//  VultisigApp
//
//  Created by Antigravity on 2025-12-11.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct CircleDepositView: View {
    let vault: Vault
    
    var body: some View {
        ZStack {
            Theme.colors.bgPrimary.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Text(NSLocalizedString("circleDepositTitle", comment: "Deposit USDC"))
                    .font(.title2)
                    .bold()
                    .foregroundStyle(Theme.colors.textPrimary)
                    .padding(.top, 20)
                
                if let address = vault.circleWalletAddress {
                    generateQRCode(from: address)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                    
                    VStack(spacing: 8) {
                        Text(NSLocalizedString("circleDepositInstruction", comment: "Send Ethereum USDC to this address"))
                            .font(.body)
                            .foregroundStyle(Theme.colors.textLight)
                        
                        Button(action: {
                            #if os(iOS)
                            UIPasteboard.general.string = address
                            #elseif os(macOS)
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(address, forType: .string)
                            #endif
                        }) {
                            HStack {
                                Text(address)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                
                                Image(systemName: "doc.on.doc")
                            }
                            .padding()
                            .background(Theme.colors.primaryAccent1)
                            .cornerRadius(12)
                            .foregroundStyle(Theme.colors.textPrimary)
                        }
                }
                .padding(.horizontal)
            }
                
                Spacer()
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    func generateQRCode(from string: String) -> Image {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        
        if let outputImage = filter.outputImage {
            if let cgimg = context.createCGImage(outputImage, from: outputImage.extent) {
                #if os(iOS)
                return Image(uiImage: UIImage(cgImage: cgimg))
                #elseif os(macOS)
                return Image(nsImage: NSImage(cgImage: cgimg, size: NSSize(width: outputImage.extent.width, height: outputImage.extent.height)))
                #endif
            }
        }
        return Image(systemName: "xmark.circle")
    }
}

// Localization keys to be added:
// "circleDepositTitle" = "Deposit USDC";
// "circleDepositInstruction" = "Send Ethereum USDC to this address";
