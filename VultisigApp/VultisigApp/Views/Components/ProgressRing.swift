//
//  ProgressRing.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-15.
//

import SwiftUI

struct ProgressRing: View {
    let progress: Double
    var gradient: AngularGradient = .progressGradient
    var fromSize: CGFloat = 80
    var toSize: CGFloat = 100
    var title: String = "done"
    
    let animation = Animation.interpolatingSpring(stiffness: 50, damping: 5, initialVelocity: 0).delay(0.3)
    
    @State var pulseIcon = false
 
    var body: some View {
        ZStack {
            ring
            done
        }
    }
 
    var ring: some View {
        Circle()
            .stroke(style: StrokeStyle(lineWidth: 8))
            .foregroundStyle(.tertiary)
            .overlay {
                progressRing
            }
            .rotationEffect(.degrees(-90))
            .frame(width: progress>=0.99 ? toSize : fromSize)
            .animation(.easeInOut(duration: progress>=0.99 ? 0.6 : 1), value: progress)
    }
    
    var progressRing: some View {
        Circle()
            .trim(from: 0, to: progress)
            .stroke(
                gradient,
                style: StrokeStyle(lineWidth: 8, lineCap: .round)
            )
    }
    
    var done: some View {
        VStack(spacing: 16) {
            logo
            doneTitle
        }
        .offset(y: 16)
        .scaleEffect(progress>=0.99 ? 1 : 0)
        .animation(.spring(duration: 1), value: progress)
    }
    
    var logo: some View {
        ZStack {
            Circle()
                .foregroundColor(.loadingGreen)
            
            if progress>=0.99 {
                Image(systemName: "checkmark")
                    .font(.title40MontserratSemiBold)
                    .foregroundColor(.neutral0)
                    .scaleEffect(pulseIcon ? 1.1 : 0)
                    .animation(animation, value: pulseIcon)
                    .onAppear {
                        pulseIcon = true
                    }
            }
        }
        .opacity(progress>=0.99 ? 1 : 0)
        .frame(width: toSize*1.2)
        .zIndex(1)
    }
    
    var doneTitle: some View {
        Text(NSLocalizedString(title, comment: ""))
            .font(.body16MenloBold)
            .foregroundColor(.neutral0)
            .offset(y: progress>=0.99 ? 0 : -50)
            .zIndex(0)
            .opacity(progress>=0.99 ? 1 : 0)
            .animation(.spring(duration: 1).delay(0.5), value: progress)
    }
}

#Preview {
    ZStack {
        Background()
        ProgressRing(progress: 0.1)
    }
}
