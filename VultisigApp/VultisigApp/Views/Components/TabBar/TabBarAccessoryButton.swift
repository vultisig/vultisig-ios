//
//  TabBarAccessoryButton.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 12/09/2025.
//

import SwiftUI

struct TabBarAccessoryButton: View {
    let icon: String
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .padding(20)
                .background(Circle().fill(Theme.colors.primaryAccent3))
        }
    }
}
