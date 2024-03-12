//
//  TokenCell.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import SwiftUI

struct TokenCell: View {
    @State var isSelected = false
    
    var body: some View {
        HStack {
            image
            text
            Spacer()
            toggle
        }
        .frame(height: 72)
        .padding(.horizontal, 16)
        .background(Color.blue600)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
    
    var image: some View {
        ZStack {
            
        }
    }
    
    var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ETH")
                .font(.body16MontserratBold)
                .foregroundColor(.neutral0)
            
            Text("Ethereum")
                .font(.body12MontserratSemiBold)
                .foregroundColor(.neutral0)
        }
    }
    
    var toggle: some View {
        Toggle("Is selected", isOn: $isSelected)
            .labelsHidden()
            .scaleEffect(0.6)
    }
}

#Preview {
    ScrollView {
        TokenCell()
    }
}
