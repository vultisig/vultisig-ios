//
//  ProgressRing.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-04-15.
//

import SwiftUI

struct ProgressRing: View {
    let progress: Double
    var gradient: AngularGradient = .progressGradient
    var fromSize: CGFloat = 300
    var toSize: CGFloat = 100
    var title: String = "done"
 
    var body: some View {
        ZStack {
            ring
            done
        }
    }
 
    var ring: some View {
        Circle()
            .stroke(style: StrokeStyle(lineWidth: 16))
            .foregroundStyle(.tertiary)
            .overlay {
                progressRing
            }
            .rotationEffect(.degrees(-90))
            .frame(width: progress>=0.99 ? toSize : fromSize)
            .animation(.easeInOut(duration: 1), value: progress)
    }
    
    var progressRing: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                gradient,
                style: StrokeStyle(lineWidth: 16, lineCap: .round)
            )
    }
    
    var done: some View {
        VStack(spacing: 16) {
            logo
            doneTitle
        }
        .offset(y: 16)
        .opacity(progress>=0.99 ? 1 : 0)
        .animation(.easeInOut(duration: 1).delay(0.5), value: progress)
    }
    
    var logo: some View {
        ZStack {
            Circle()
                .foregroundColor(.loadingGreen)
            
            Image(systemName: "checkmark")
                .font(.title40MontserratSemiBold)
                .foregroundColor(.neutral0)
        }
        .frame(width: toSize*1.2)
        .zIndex(1)
    }
    
    var doneTitle: some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
            .offset(y: progress>=0.99 ? 0 : -50)
            .zIndex(0)
    }
}

#Preview {
    ZStack {
        Background()
        ProgressRing(progress: 0)
    }
}
