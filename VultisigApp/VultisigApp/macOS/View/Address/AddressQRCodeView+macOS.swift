//
//  AddressQRCodeView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension AddressQRCodeView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(true)
    }

    var main: some View {
        VStack {
            headerMac
            view
        }
    }

    var headerMac: some View {
        AddressQRCodeHeader(
            vault: vault,
            groupedChain: groupedChain,
            shareSheetViewModel: shareSheetViewModel
        )
    }
}
#endif
