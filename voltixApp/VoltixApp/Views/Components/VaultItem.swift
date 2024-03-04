//
//  VaultItem.swift
//  VoltixApp
//
//  Created by Mac on 05.02.2024.
//

import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct VaultItem: View {
    @Binding var presentationStack: [CurrentScreen]
    let coinName: String
    let usdAmount: String
    let showAmount: Bool
    let address: String
    let isRadio: Bool
    let radioIcon: String
    let showButtons: Bool
    let coin: Coin
    
    @State private var showingQRCode = false
    @State private var showingShareSheet = false
    @State private var showingToast = false
    @State private var toastMessage = "Address copied to clipboard"
    
    func showToast() {
        withAnimation {
            showingToast = true
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(coinName)
                    .font(Font.custom("Menlo", size: 20).weight(.bold))
                
                if showButtons {
                    Spacer()
                    Button(action: {
                        UIPasteboard.general.string = self.address
                        self.showingToast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.showingToast = false
                        }
                    }) {
                        Image(systemName: "square.on.square")
                            .resizable()
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .overlay(
                        showingToast
                            ? ToastView(message: toastMessage)
                            .transition(.opacity)
                            .animation(.easeInOut, value: showingToast)
                            : nil
                    )
                    
                    Spacer().frame(width: 20)
                    Button(action: { self.showingShareSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .resizable()
                            .frame(width: 16, height: 20)
                        
                    }.buttonStyle(PlainButtonStyle())
                    Spacer()
                        .frame(width: 20)
                        .sheet(isPresented: $showingShareSheet) {
                            ShareSheet(items: [self.address])
                        }
                    Button(action: {
                        self.showingQRCode = true
                    }) {
                        Image(systemName: "qrcode")
                            .resizable()
                            .frame(width: 20, height: 20)
                        
                    }.buttonStyle(PlainButtonStyle())
                        .sheet(isPresented: $showingQRCode) {
                            QRCodeView(qrCodeImage: Utils.getQrImage(data: address.data(using: .utf8), size: 100))
                                .padding()
                        }
                    Spacer().frame(width: 20)
                    Button(action: {
                        
                        if coin.chain.name.lowercased() == "bitcoin" {
                            presentationStack.append(.bitcoinTransactionsListView)
                        } else if coin.chain.name.lowercased() == "ethereum" {
                            if !coin.contractAddress.isEmpty {
                                presentationStack.append(.erc20TransactionsListView(coin.contractAddress))
                            } else {
                                presentationStack.append(.ethereumTransactionsListView)
                            }
                        }
                    }) {
                        Image(systemName: "cube.transparent")
                            .resizable()
                            .frame(width: 16, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                if showAmount {
                    Spacer()
                    
                    Text(usdAmount)
                        .font(Font.custom("Menlo", size: 20))
                        .multilineTextAlignment(.trailing)
                }
            }
            HStack {
                Text(address)
                    .font(Font.custom("Montserrat", size: 13).weight(.medium))
                    .lineSpacing(19.50)
            }
            .padding(.vertical)
        }
    }
}
