//
//  CustomTokenHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-08.
//

import SwiftUI

struct GeneralMacHeader: View {
    let title: String
    
    var showActions: Bool = true
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        HStack {
            if showActions {
                leadingAction
            }
            
            Spacer()
            text
            Spacer()
            
            if showActions {
                leadingAction.opacity(0)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
        .background(Color.backgroundBlue)
    }
    
    var leadingAction: some View {
        NavigationBackButton()
    }
    
    var text: some View {
        Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(.neutral0)
            .font(.title3)
    }
}

#Preview {
    GeneralMacHeader(title: "Ethereum")
}
