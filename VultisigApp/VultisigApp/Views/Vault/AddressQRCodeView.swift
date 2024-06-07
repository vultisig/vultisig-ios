//
//  AddressQRCodeView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-08.
//

import SwiftUI

struct AddressQRCodeView: View {
    let addressData: String
    @Binding var showSheet: Bool
    @Binding var isLoading: Bool
    
    let padding: CGFloat = 30
    
    @State var qrCodeImage: Image? = nil
    @StateObject var shareSheetViewModel = ShareSheetViewModel()
    
    @Environment(\.displayScale) var displayScale
    
    var body: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("address", comment: "AddressQRCodeView title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackSheetButton(showSheet: $showSheet)
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                NavigationQRShareButton(title: "joinKeygen", renderedImage: shareSheetViewModel.renderedImage)
            }
        }
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
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
            .multilineTextAlignment(.center)
            .padding(.horizontal, padding)
    }
    
    var qrCode: some View {
        GeometryReader { geometry in
            qrCodeImage?
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
    
    private func setData() {
        isLoading = false
        qrCodeImage = Utils.getQrImage(
            data: addressData.data(using: .utf8), size: 100)
        
        guard let qrCodeImage else {
            return
        }
        
        shareSheetViewModel.render(
            title: addressData,
            qrCodeImage: qrCodeImage,
            displayScale: displayScale
        )
    }
}

#Preview {
    AddressQRCodeView(addressData: "", showSheet: .constant(true), isLoading: .constant(false))
}
