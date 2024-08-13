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
    
#if os(iOS)
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
#endif
    
    var body: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(true)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(NSLocalizedString("address", comment: "AddressQRCodeView title"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackSheetButton(showSheet: $showSheet)
            }
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationQRShareButton(title: "joinKeygen", renderedImage: shareSheetViewModel.renderedImage)
            }
        }
#endif
    }
    
    var main: some View {
        VStack {
#if os(macOS)
            headerMac
#endif
            view
        }
    }
    
    var headerMac: some View {
        AddressQRCodeHeader(shareSheetViewModel: shareSheetViewModel)
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
        qrCodeImage?
            .resizable()
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(24)
            .aspectRatio(contentMode: .fit)
            .background(Color.turquoise600.opacity(0.15))
            .cornerRadius(10)
            .overlay (
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 2, dash: [56]))
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
            title: addressData,
            qrCodeImage: qrCodeImage,
            displayScale: displayScale
        )
    }
}

#Preview {
    AddressQRCodeView(addressData: "", showSheet: .constant(true), isLoading: .constant(false))
}
