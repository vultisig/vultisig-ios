//
//  ProgressBar.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-13.
//

import SwiftUI

struct ProgressBar: View {
    let progress: Double
    
    var body: some View {
        content
            .padding(.horizontal, 16)
            .frame(height: 10)
    }
    
    var base: some View {
        RoundedRectangle(cornerRadius: 30)
            .frame(height: 10)
            .foregroundColor(.blue400)
    }
}

#Preview {
    ProgressBar(progress: 1)
}
