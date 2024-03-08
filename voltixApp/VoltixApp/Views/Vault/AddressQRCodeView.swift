//
//  AddressQRCodeView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct AddressQRCodeView: View {
    
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
                NavigationBackButton()
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
        Text("bc1psrjtwm7682v6nhx2uwfgcfelrennd7pcvqq7v6w")
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .lineLimit(1)
    }
    
    var qrCode: some View {
        GeometryReader { geometry in
            ZStack {
                // Add QR Code here...
            }
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
    AddressQRCodeView()
}
