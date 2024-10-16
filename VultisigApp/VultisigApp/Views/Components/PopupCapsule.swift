//
//  PopupCapsule.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-13.
//

import SwiftUI

struct PopupCapsule: View {
    let text: String
    @Binding var showPopup: Bool
    
    @State var offset: CGFloat = 100
    @State var showText: Bool = false
    
    var body: some View {
        VStack {
            Spacer()
            capsule
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onChange(of: showPopup) { oldValue, newValue in
            startAnimation()
        }
    }
    
    var capsule: some View {
        Text(showText ? NSLocalizedString(text, comment: "") : "")
            .foregroundColor(.neutral0.opacity(showText ? 1 : 0))
            .font(.body14MenloBold)
            .padding()
            .padding(.horizontal, showText ? 16 : 8)
            .background(Color.blue200)
            .cornerRadius(100)
            .offset(y: offset)
    }
    
    private func startAnimation() {
        guard showPopup else {
            return
        }
        
        withAnimation {
            offset = -50
        }
            
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                showText = true
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                offset = 100
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
            withAnimation {
                showText = false
                showPopup = false
            }
        }
    }
}

#Preview {
    @Previewable @State var show = true
    
    return ZStack {
        Background()
        
        PopupCapsule(text: "addressCopied", showPopup: $show)
    }
}
