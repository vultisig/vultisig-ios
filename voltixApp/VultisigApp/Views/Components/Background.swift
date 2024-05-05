//
//  Background.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-19.
//

import SwiftUI

struct Background: View {
    var color = Color.backgroundBlue
    
    var body: some View {
        color
            .ignoresSafeArea()
    }
}

#Preview {
    Background()
}
