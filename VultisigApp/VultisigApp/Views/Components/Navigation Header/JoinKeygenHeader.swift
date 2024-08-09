//
//  JoinKeygenHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-08.
//

import SwiftUI

struct JoinKeygenHeader: View {
    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            trailingAction
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }
    
    var leadingAction: some View {
        NavigationBackButton()
    }
    
    var text: some View {
        Text(NSLocalizedString("joinKeygen", comment: "Join keygen/reshare"))
            .foregroundColor(.neutral0)
            .font(.title3)
    }
    
    var trailingAction: some View {
        NavigationHelpButton()
    }
}

#Preview {
    JoinKeygenHeader()
}
