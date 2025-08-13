//
//  FunctionCallHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-08.
//

import SwiftUI

struct FunctionCallHeader: View {
    @ObservedObject var functionCallViewModel: FunctionCallViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            leadingAction.opacity(0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }
    
    var leadingAction: some View {
        let isDone = functionCallViewModel.currentIndex==5
        
        return Button {
            handleBackTap()
        } label: {
            NavigationBlankBackButton()
        }
        .opacity(isDone ? 0 : 1)
        .disabled(isDone)
    }
    
    var text: some View {
        Text(NSLocalizedString(functionCallViewModel.currentTitle, comment: "SendCryptoView title"))
            .foregroundColor(Theme.colors.textPrimary)
            .font(.title3)
    }
    
    private func handleBackTap() {
        guard functionCallViewModel.currentIndex>1 else {
            dismiss()
            return
        }
        
        functionCallViewModel.handleBackTap()
    }
}

#Preview {
    FunctionCallHeader(functionCallViewModel: FunctionCallViewModel())
}
