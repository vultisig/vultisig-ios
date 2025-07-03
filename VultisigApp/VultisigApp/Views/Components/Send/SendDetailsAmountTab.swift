//
//  SendDetailsAmountTab.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-07-02.
//

import SwiftUI

struct SendDetailsAmountTab: View {
    @ObservedObject var tx: SendTransaction
    @ObservedObject var viewModel: SendDetailsViewModel
    
    @State var isExpanded: Bool = true
    
    var body: some View {
        content
    }
    
    var content: some View {
        VStack(spacing: 16) {
            titleSection
            
            if isExpanded {
                separator
                amountFieldSection
            }
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue200, lineWidth: 1)
        )
        .padding(1)
    }
    
    var titleSection: some View {
        HStack {
            Text(NSLocalizedString("amount", comment: ""))
                .font(.body14BrockmannMedium)
                .foregroundColor(.neutral0)
            
            Spacer()
            gasSelector
        }
    }
    
    var separator: some View {
        LinearSeparator()
    }
    
    var gasSelector: some View {
        Button {
            
        } label: {
            editLabel
        }
    }
    
    var editLabel: some View {
        Image(systemName: "fuelpump")
            .foregroundColor(.neutral0)
            .font(.body16BrockmannMedium)
    }
    
    var amountFieldSection: some View {
        SendDetailsAmountTextField()
    }
}

#Preview {
    SendDetailsAmountTab(tx: SendTransaction(), viewModel: SendDetailsViewModel())
}
