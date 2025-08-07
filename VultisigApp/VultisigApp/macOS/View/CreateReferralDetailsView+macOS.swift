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
        VStack(spacing: 0) {
            header
            content
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
    
    var header: some View {
        HStack {
            GeneralMacHeader(title: "createReferral")
            infoButton
        }
        .background(Theme.colors.bgPrimary)
    }
}
#endif
