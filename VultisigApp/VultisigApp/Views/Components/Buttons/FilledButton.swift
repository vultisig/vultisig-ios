//
//  FilledButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct FilledButton: View {
    let title: String
    var icon: String = ""
    var background: Color = Color.turquoise600
    
    var body: some View {
        HStack(spacing: 10) {
            if !icon.isEmpty {
                image
            }
            text
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(background)
        .cornerRadius(100)
    }
    
    var image: some View {
        Image(systemName: icon)
            .font(.body16Menlo)
            .foregroundColor(.blue600)
    }
}

#Preview {
    VStack {
        FilledButton(title: "start")
        FilledButton(title: "start", icon: "plus")
    }
}
