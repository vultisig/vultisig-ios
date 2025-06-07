//
//  KeygenProgressContainer.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-01-29.
//

import SwiftUI
import RiveRuntime

struct KeygenProgressContainer: View {
    let progressCounter: Double
    
    @State var animationVMCheckmark: RiveViewModel? = nil
    @State var animationVMLoader: RiveViewModel? = nil
    
    var body: some View {
        ZStack {
            content
            progressBar
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .onAppear {
            animationVMCheckmark = RiveViewModel(fileName: "CreatingVaultCheckmark", autoPlay: true)
            animationVMLoader = RiveViewModel(fileName: "ConnectingWithServer", autoPlay: true)
        }
        .onDisappear {
            animationVMCheckmark?.stop()
            animationVMLoader?.stop()
        }
    }
    
    var content: some View {
        VStack {
            Spacer()
            
            VStack(alignment: .leading, spacing: 12) {
                getCell(for: "preparingVault", isComplete: progressCounter>1)
                
                if progressCounter>1 {
                    getCell(for: "generatingECDSA", isComplete: progressCounter>2)
                }
                    
                if progressCounter>2 {
                    getCell(for: "generatingEdDSA", isComplete: progressCounter>3)
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .background(Color.blue600)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.blue200, lineWidth: 1)
            )
        }
        .animation(.easeInOut, value: progressCounter)
    }
    
    var progressBar: some View {
        VStack {
            Spacer()
            KeygenProgressBar(progress: progressCounter/4)
                .frame(height: 5)
                .offset(y: 2)
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 22)
    }
    
    private func getCell(for title: String, isComplete: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                if isComplete {
                    animationVMCheckmark?.view()
                } else {
                    animationVMLoader?.view()
                }
            }
            .frame(width: 24, height: 24)
            
            Text(NSLocalizedString(title, comment: ""))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
        }
    }
}

#Preview {
    KeygenProgressContainer(progressCounter: 0)
}
