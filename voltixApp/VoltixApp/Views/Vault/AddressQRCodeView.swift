//
//  AddressQRCodeView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct AddressQRCodeView: View {
    let addressData: String
    @Binding var showSheet: Bool
    
    let padding: CGFloat = 30
    
    var body: some View {
        ZStack {
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("address", comment: "Swap button text"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackSheetButton(showSheet: $showSheet)
            }
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack(spacing: 50) {
            address
            qrCode
            Spacer()
        }
        .padding(.top, 30)
    }
    
    var address: some View {
        Text(addressData)
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
            .padding(.horizontal, padding)
    }
    
    var qrCode: some View {
        GeometryReader { geometry in
            Utils.getQrImage(
                data: addressData.data(using: .utf8), size: 100)
            .resizable()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(24)
            .frame(maxWidth: .infinity)
            .frame(height: geometry.size.width-(2*padding))
            .background(Color.turquoise600.opacity(0.15))
            .cornerRadius(10)
            .overlay (
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 2, dash: [56]))
            )
            .padding(.horizontal, padding)
        }
    }
}

#Preview {
    AddressQRCodeView(addressData: "", showSheet: .constant(true))
}
