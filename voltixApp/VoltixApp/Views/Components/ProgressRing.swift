//
//  ProgressRing.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-15.
//

import SwiftUI

struct ProgressRing: View {
    var gradient: AngularGradient = .progressGradient
    let progress: Double
 
    var body: some View {
        ZStack {
            ring
                .frame(width: 300)
        }
        .animation(.easeInOut, value: progress)
    }
 
    var ring: some View {
        Circle()
            .stroke(style: StrokeStyle(lineWidth: 16))
            .foregroundStyle(.tertiary)
            .overlay {
                progressRing
            }
            .rotationEffect(.degrees(-90))
    }
    
    var progressRing: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                gradient,
                style: StrokeStyle(lineWidth: 16, lineCap: .round)
            )
    }
}

#Preview {
    ProgressRing(progress: 0.25)
}
