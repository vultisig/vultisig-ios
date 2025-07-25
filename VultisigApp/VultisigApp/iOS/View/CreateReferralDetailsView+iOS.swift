//
//  CreateReferralDetailsView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-07.
//

#if os(iOS)
import SwiftUI

extension CreateReferralDetailsView {
    var container: some View {
        content
            .navigationTitle(NSLocalizedString("createReferral", comment: ""))
            .toolbar {
                ToolbarItem(placement: Placement.topBarTrailing.getPlacement()) {
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
    }
}
#endif
