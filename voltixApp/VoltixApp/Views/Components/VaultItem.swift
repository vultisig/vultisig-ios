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
          .overlay(
            showingToast
              ? AnyView(
                ToastView(message: toastMessage)
                  .animation(.easeInOut)
                  .transition(.opacity)) : AnyView(EmptyView()))

          Spacer().frame(width: 8)
          Button(action: { self.showingShareSheet = true }) {
            Image(systemName: "square.and.arrow.up")
              .resizable()
              .frame(width: 16, height: 20)

          }
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

          }
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
