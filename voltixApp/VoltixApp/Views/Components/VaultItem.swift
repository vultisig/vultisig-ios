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

  let coinName: String
  let usdAmount: String
  let showAmount: Bool
  let address: String
  let isRadio: Bool
  let radioIcon: String
  let showButtons: Bool
  let onClick: () -> Void
  init(
    coinName: String,
    usdAmount: String,
    showAmount: Bool = true,
    address: String,
    isRadio: Bool = false,
    radioIcon: String = "largecircle.fill.circle",
    showButtons: Bool = false,
    onClick: @escaping () -> Void
  ) {
    self.coinName = coinName
    self.usdAmount = usdAmount
    self.showAmount = showAmount
    self.address = address
    self.isRadio = isRadio
    self.radioIcon = radioIcon
    self.showButtons = showButtons
    self.onClick = onClick
  }

  var body: some View {
    smallItem(
      coinName: self.coinName,
      usdAmount: self.usdAmount,
      showAmount: self.showAmount,
      address: self.address,
      isRadio: self.isRadio,
      radioIcon: self.radioIcon,
      showButtons: self.showButtons
    )

  }
}

private struct smallItem: View {
  @State private var showingQRCode = false
  @State private var showingShareSheet = false
  @State private var showingToast = false
  @State private var toastMessage = "Address copied to clipboard"

  let coinName: String
  let usdAmount: String
  let showAmount: Bool
  let address: String
  let isRadio: Bool
  let radioIcon: String
  let showButtons: Bool

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
          .foregroundColor(.black)
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
              .foregroundColor(.black)
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
              .foregroundColor(.black)
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
              .foregroundColor(.black)
          }
          .sheet(isPresented: $showingQRCode) {
            if let qrCodeImage = ActivityViewModel.generateHighQualityQRCode(from: address) {
              QRCodeView(qrCodeImage: qrCodeImage)
                .padding()
            } else {
              Text("Failed to generate QR Code")
            }
          }
        }
        Spacer()

        Text(usdAmount)
          .font(Font.custom("Menlo", size: 20))
          .multilineTextAlignment(.trailing)
          .foregroundColor(.black)

      }
      HStack {
        Text(address)
          .font(Font.custom("Montserrat", size: 13).weight(.medium))
          .lineSpacing(19.50)
          .foregroundColor(.black)
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
  VaultItem(
    coinName: "THORChain",
    usdAmount: "11.1",
    address: "thor1cfelrennd7pcvqq7v6w7682v6nhx2uwfg",
    onClick: {

    }
  )
}
