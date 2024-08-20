//
//  AddressQRCodeHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-09.
//

import SwiftUI

struct AddressQRCodeHeader: View {
    @ObservedObject var shareSheetViewModel: ShareSheetViewModel
    
    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            trailingAction
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }
    
    var leadingAction: some View {
        NavigationBackButton()
    }
    
    var text: some View {
        Text(NSLocalizedString("address", comment: "AddressQRCodeView title"))
            .foregroundColor(.neutral0)
            .font(.title3)
    }
    
    var trailingAction: some View {
        NavigationQRShareButton(title: "joinKeygen", renderedImage: shareSheetViewModel.renderedImage)
    }
}

#Preview {
    AddressQRCodeHeader(shareSheetViewModel: ShareSheetViewModel())
}
