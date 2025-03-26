//
//  SwapPercentageButtons.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-03-25.
//

import SwiftUI

struct SwapPercentageButtons: View {
    @ObservedObject var tx: SwapTransaction
    @ObservedObject var swapViewModel: SwapCryptoViewModel
    
    var body: some View {
        container
            .frame(maxWidth: .infinity)
    }
    
    var separator: some View {
        Rectangle()
            .frame(height: 1)
            .foregroundColor(.blue400)
    }
    
    var buttons: some View {
        HStack(spacing: 8) {
            button1
            button2
            button3
            button4
        }
    }
    
    var button1: some View {
        Button {
            
        } label: {
            getPercentageCell(for: "25")
        }
    }
    
    var button2: some View {
        Button {
            
        } label: {
            getPercentageCell(for: "50")
        }
    }
    
    var button3: some View {
        Button {
            
        } label: {
            getPercentageCell(for: "75")
        }
    }
    
    var button4: some View {
        Button {
            
        } label: {
            getPercentageCell(for: "100")
        }
    }
    
    private func getPercentageCell(for text: String) -> some View {
        Text(text + "%")
            .font(.body12BrockmannMedium)
            .foregroundColor(.neutral0)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.blue600)
            .cornerRadius(32)
    }
}

#Preview {
    SwapPercentageButtons(
        tx: SwapTransaction(),
        swapViewModel: SwapCryptoViewModel()
    )
}
