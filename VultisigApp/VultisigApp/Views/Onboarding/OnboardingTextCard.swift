//
//  OnboardingTextCard.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-23.
//

import SwiftUI

struct OnboardingTextCard: View {
    let index: Int
    let textPrefix: String
    
    var deviceCount: String? = nil
    
    @State var showText: Bool = false
    
    var body: some View {
        Group {
            Text(NSLocalizedString("\(textPrefix)\(index+1)Text1", comment: ""))
                .foregroundColor(.neutral0) +
            Text(deviceCount ?? "")
                .foregroundColor(.neutral0) +
            Text(NSLocalizedString("\(textPrefix)\(index+1)Text2", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient) +
            Text(NSLocalizedString("\(textPrefix)\(index+1)Text3", comment: ""))
                .foregroundColor(.neutral0) +
            Text(NSLocalizedString("\(textPrefix)\(index+1)Text4", comment: ""))
                .foregroundStyle(LinearGradient.primaryGradient)
        }
        .font(.body28BrockmannMedium)
        .frame(maxWidth: 1024)
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
        .multilineTextAlignment(.center)
        .opacity(showText ? 1 : 0)
        .offset(y: showText ? 0 : 50)
        .blur(radius: showText ? 0 : 10)
        .onAppear {
            setData()
        }
    }
    
    private func setData() {
        withAnimation {
            showText = true
        }
    }
}

#Preview {
    OnboardingTextCard(index: 0, textPrefix: "OnboardingCard")
}
