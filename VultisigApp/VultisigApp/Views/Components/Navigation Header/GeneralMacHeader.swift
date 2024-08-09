//
//  CustomTokenHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-08.
//

import SwiftUI

struct GeneralMacHeader: View {
    let title: String
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            leadingAction.opacity(0)
        }
        .padding(.vertical, 8)
    }
    
    var leadingAction: some View {
        NavigationBackButton()
    }
    
    var text: some View {
        Text(title)
            .foregroundColor(.neutral0)
            .font(.title3)
    }
}

#Preview {
    GeneralMacHeader(title: "Ethereum")
}
