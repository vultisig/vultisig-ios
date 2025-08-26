//
//  CustomTokenHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-08.
//

import SwiftUI

struct GeneralMacHeader: View {
    @Environment(\.screenToolbarTrailing) private var trailing
    
    let title: String
    
    var showActions: Bool = true
    
    var body: some View {
        HStack(alignment: .center) {
            HStack {
                if showActions {
                    leadingAction
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            text
            
            HStack {
                trailing
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .frame(height: 40)
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
