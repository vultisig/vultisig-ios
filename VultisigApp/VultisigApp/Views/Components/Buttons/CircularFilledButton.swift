//
//  CircularFilledButton.swift
//  VultisigApp
//
//  Created by Enrique Souza Soares on 07/06/24.
//

import SwiftUI

struct CircularFilledButton: View {
    let icon: String
    var background: Color = Color.turquoise600
    
    var body: some View {
        ZStack {
            Circle()
                .fill(background)
                .frame(width: 44, height: 44)
            
            Image(systemName: icon)
                .font(.body16Menlo)
                .foregroundColor(.white)
        }
    }
}

#Preview {
    VStack {
        CircularFilledButton(icon: "magnifyingglass")
        CircularFilledButton(icon: "plus")
    }
}

