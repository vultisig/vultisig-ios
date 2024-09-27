//
//  AddressQRCodeView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
import SwiftUI

extension AddressQRCodeView {
    private var idiom : UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(NSLocalizedString("address", comment: "AddressQRCodeView title"))
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                NavigationBackSheetButton(showSheet: $showSheet)
            }
            ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
                NavigationQRShareButton(
                    vault: vault,
                    type: .Address,
                    renderedImage: shareSheetViewModel.renderedImage,
                    title: groupedChain.name
                )
            }
        }
    }
    
    var main: some View {
        view
    }
}
#endif
