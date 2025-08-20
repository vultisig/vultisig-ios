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
        .background(Theme.colors.bgPrimary)
    }
    
    var leadingAction: some View {
        NavigationBackButton()
    }
    
    var text: some View {
        Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(.title3)
    }
}

#Preview {
    GeneralMacHeader(title: "Ethereum")
}
