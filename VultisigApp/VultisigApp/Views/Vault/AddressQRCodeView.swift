//
//  AddressQRCodeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct AddressQRCodeView: View {
    let addressData: String
    let vault: Vault
    let groupedChain: GroupedChain
    @Binding var showSheet: Bool
    @Binding var isLoading: Bool
    
    let padding: CGFloat = 30
    
    @State var qrCodeImage: Image? = nil
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    
    @Environment(\.displayScale) var displayScale
    
    var body: some View {
        content
    }
    
    var view: some View {
        VStack(spacing: 50) {
            address
            qrCode
            Spacer()
        }
        .padding(.top, 30)
        .onAppear {
            setData()
        }
    }
    
    var address: some View {
        Text(addressData)
            .font(Theme.fonts.caption12)
            .foregroundColor(Theme.colors.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, padding)
    }
    
    var qrCode: some View {
        qrCodeImage?
            .resizable()
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(24)
            .aspectRatio(contentMode: .fit)
            .background(Theme.colors.bgSurface1)
            .cornerRadius(20)
            .overlay (
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Theme.colors.bgButtonPrimary, style: StrokeStyle(lineWidth: 2, dash: [100]))
            )
            .padding(.horizontal, padding)
            .frame(maxWidth: .infinity, alignment: .center)
    }
    
    private func setData() {
        isLoading = false
        qrCodeImage = Utils.getQrImage(
            data: addressData.data(using: .utf8), size: 100)
        
        guard let qrCodeImage else {
            return
        }
        
        shareSheetViewModel.render(
            qrCodeImage: qrCodeImage,
            qrCodeData: nil,
            displayScale: displayScale,
            type: .Address,
            addressData: addressData
        )
    }
}

#Preview {
    AddressQRCodeView(
        addressData: "123456789", 
        vault: Vault.example, 
        groupedChain: GroupedChain.example,
        showSheet: .constant(true),
        isLoading: .constant(false)
    )
}
