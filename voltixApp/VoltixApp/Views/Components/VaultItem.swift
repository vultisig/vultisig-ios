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
          Spacer().frame(width: 10)
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

          Spacer().frame(width: 8)
          Button(action: { self.showingShareSheet = true }) {
            Image(systemName: "square.and.arrow.up")
              .resizable()
              .frame(width: 16, height: 20)

          }.buttonStyle(PlainButtonStyle())
          Spacer()
            .frame(width: 8)
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
            if let qrCodeImage = ActivityViewModel.generateHighQualityQRCode(from: address) {
              QRCodeView(qrCodeImage: qrCodeImage)
                .padding()
            } else {
              Text("Failed to generate QR Code")
            }
          }
          Spacer().frame(width: 8)
          Button(action: {
              presentationStack.append(.bitcoinTransactionsListView)
          }) {
            Image(systemName: "cube.transparent")
              .resizable()
              .frame(width: 16, height: 20)
          }
          .buttonStyle(PlainButtonStyle())

        }
        Spacer()

        Text(usdAmount)
          .font(Font.custom("Menlo", size: 20))
          .multilineTextAlignment(.trailing)

      }
      HStack {
        Text(address)
          .font(Font.custom("Montserrat", size: 13).weight(.medium))
          .lineSpacing(19.50)

        Spacer()
        if isRadio {
          Image(systemName: radioIcon)
            .renderingMode(.original)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 20, height: 20)
            .modifier(ColorInvert())
        }
      }
    }
  }

}

#Preview {
    VaultItem(presentationStack: .constant([]), coinName: "Bitcoin", usdAmount: "US$10,000,000.98", showAmount: true, address: "3JK2dFmWA58A3kukgw1yybotStGAFaV6Sg", isRadio: true, radioIcon: "String", showButtons: true)
}
