//
//  ImportWalletView2.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftUI

struct ImportWalletView2: View {
    
    var body: some View {
        ZStack {
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("import", comment: "Import title"))
        .navigationBarTitleDisplayMode(.inline)
        .font(.body20MontserratSemiBold)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        VStack(spacing: 15) {
            instruction
            uploadSection
            Spacer()
            button
        }
        .padding(.top, 30)
    }
    
    var instruction: some View {
        Text(NSLocalizedString("enterPreviousVault", comment: "Import Vault instruction"))
            .font(.body12Menlo)
            .foregroundColor(.neutral0)
    }
    
    var uploadSection: some View {
        VStack(spacing: 26) {
            Image("FileIcon")
            uploadText
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(Color.turquoise600.opacity(0.15))
        .cornerRadius(10)
        .overlay (
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.turquoise600, style: StrokeStyle(lineWidth: 1, dash: [10]))
        )
        .padding(.horizontal, 30)
    }
    
    var uploadText: some View {
        Text(NSLocalizedString("uploadFile", comment: "Upload file details"))
            .font(.body12MontserratSemiBold)
            .foregroundColor(.neutral0)
    }
    
    var button: some View {
        FilledButton(title: "continue")
            .padding(40)
        
    }
}

#Preview {
    ImportWalletView2()
}
