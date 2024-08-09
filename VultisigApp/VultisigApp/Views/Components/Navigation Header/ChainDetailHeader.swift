//
//  ChainDetailHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-07.
//

import SwiftUI

struct ChainDetailHeader: View {
    let title: String
    let refreshAction: () -> Void
    
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
        Text(title)
            .foregroundColor(.neutral0)
            .font(.title3)
    }
    
    var trailingAction: some View {
        NavigationRefreshButton() {
            refreshAction()
        }
    }
}

#Preview {
    func refreshAction() {}
    return ChainDetailHeader(title: "Ethereum", refreshAction: refreshAction)
}
