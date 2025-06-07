//
//  FilledButton.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct FilledButton: View {
    var title: String = ""
    var icon: String = ""
    var textColor: Color = Color.blue600
    var background: Color = Color.turquoise600
    var showLoader: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            if !icon.isEmpty {
                image
            }
            
            if !title.isEmpty {
                text
            }
            
            if showLoader {
                loader
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(background)
        .cornerRadius(100)
    }
    
    var image: some View {
        Image(systemName: icon)
            .font(.body14BrockmannSemiBold)
            .foregroundColor(.blue600)
    }
    
    var loader: some View {
        ProgressView()
            .scaleEffect(0.7)
    }
}

#Preview {
    VStack {
        FilledButton(title: "start")
        FilledButton(title: "start", icon: "plus")
    }
}
