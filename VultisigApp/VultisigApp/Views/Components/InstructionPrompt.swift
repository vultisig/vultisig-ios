//
//  InstructionPrompt.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-16.
//

import SwiftUI

struct InstructionPrompt: View {
    let networkType: NetworkPromptType
    
    var body: some View {
        content
    }
    
    var phoneContent: some View {
        VStack(spacing: 12) {
            networkType.getImage()
                .font(.body20MenloMedium)
                .foregroundColor(.turquoise600)
            
            Text(networkType.getInstruction())
                .font(.body10Menlo)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
        }
        .frame(height: 60)
    }
    
    var padContent: some View {
        VStack(spacing: 12) {
            networkType.getImage()
                .font(.title30MenloUltraLight)
                .foregroundColor(.turquoise600)
            
            Text(networkType.getInstruction())
                .font(.body12Menlo)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
        }
        .frame(height: 80)
    }
}

#Preview {
    ZStack {
        Background()
        InstructionPrompt(networkType: .Internet)
    }
}
