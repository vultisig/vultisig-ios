//
//  KeygenViewInstructions.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-31.
//

import SwiftUI

struct KeygenViewInstructions: View {
    @State var tabIndex = 0
    
    var body: some View {
        card1
    }
    
    var card1: some View {
        TabView(selection: $tabIndex) {
            ForEach(0..<7) { index in
                getCard(for: index)
            }
        }
        .tabViewStyle(PageTabViewStyle())
        .frame(maxHeight: .infinity)
    }
    
    private func getCard(for index: Int) -> some View {
        VStack(spacing: 22) {
            getTitle(for: index)
        }
        .tag(index)
    }
    
    private func getTitle(for index: Int) -> some View {
        Text(NSLocalizedString("keygenInstructionsCar\(index+1)Title", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body16MontserratBold)
    }
}

#Preview {
    ZStack {
        Background()
        KeygenViewInstructions()
    }
}
