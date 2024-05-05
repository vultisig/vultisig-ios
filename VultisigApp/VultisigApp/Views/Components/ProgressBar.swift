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
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                base
                loadingBar(for: geometry.size.width)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 10)
    }
    
    var base: some View {
        RoundedRectangle(cornerRadius: 30)
            .frame(height: 10)
            .foregroundColor(.blue400)
    }
    
    func loadingBar(for width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 30)
            .frame(width: width*progress, height: 10)
            .foregroundStyle(LinearGradient.progressGradient)
            .animation(.easeInOut, value: progress)
    }
}

#Preview {
    ProgressBar(progress: 0.25)
}
