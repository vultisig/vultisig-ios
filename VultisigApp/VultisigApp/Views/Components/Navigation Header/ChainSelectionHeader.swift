//
//  ChainSelectionHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-09.
//

import SwiftUI

struct ChainSelectionHeader: View {
    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            leadingAction.opacity(0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }
    
    var leadingAction: some View {
        NavigationBackButton()
    }
    
    var text: some View {
        Text(NSLocalizedString("chooseChains", comment: "AddressQRCodeView title"))
            .foregroundColor(.neutral0)
            .font(.title3)
    }
}

#Preview {
    ChainSelectionHeader()
}
