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
        ZStack {
#if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                phoneContent
            } else {
                padContent
            }
#endif
        }
    }
    
    var phoneContent: some View {
        VStack(spacing: 12) {
            networkType.getImage()
                .font(.body20MenloMedium)
                .foregroundColor(.turquoise600)
            
            Text(networkType.getInstruction())
                .font(.body10Menlo)
                .foregroundColor(.neutral0)
                .frame(maxWidth: 350)
                .multilineTextAlignment(.center)
        }
    }
    
    var padContent: some View {
        VStack(spacing: 12) {
            networkType.getImage()
                .font(.title30MenloUltraLight)
                .foregroundColor(.turquoise600)
            
            Text(networkType.getInstruction())
                .font(.body12Menlo)
                .foregroundColor(.neutral0)
                .frame(maxWidth: 250)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    ZStack {
        Background()
        InstructionPrompt(networkType: .Internet)
    }
}
