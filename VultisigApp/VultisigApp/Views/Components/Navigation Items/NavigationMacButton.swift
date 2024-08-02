//
//  NavigationMacButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-02.
//

import SwiftUI

struct NavigationMacButton: View {
    let icon: String
    let title: String
    var tint: Color = .neutral0
    
    var body: some View {
        HStack(spacing: 12) {
            logo
            text
        }
    }
    
    var logo: some View {
        Image(systemName: "chevron.backward")
            .foregroundColor(tint)
            .font(.body18Menlo)
    }
    
    var text: some View {
        Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(tint)
            .font(.body14Menlo)
    }
}

#Preview {
    NavigationMacButton(icon: "chevron.backward", title: "settings")
}
