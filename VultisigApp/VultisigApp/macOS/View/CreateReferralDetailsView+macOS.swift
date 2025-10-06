//
//  CreateReferralDetailsView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-07.
//

#if os(macOS)
import SwiftUI

extension CreateReferralDetailsView {
    var container: some View {
        content
            .crossPlatformToolbar("createReferral".localized) {
                CustomToolbarItem(placement: .trailing) {
                    infoButton
                }
            }
    }
    
    var infoButton: some View {
        Button {
            showTooltip.toggle()
        } label: {
            infoLabel
        }
        .padding(.trailing, 24)
    }
}
#endif
