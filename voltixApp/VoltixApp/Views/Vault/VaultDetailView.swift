//
//  VaultDetailView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-07.
//

import SwiftUI

struct VaultDetailView: View {
    var body: some View {
        ZStack {
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle("Ethereum")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationRefreshButton()
            }
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        ScrollView {
            list
            addButton
        }
        .padding(.top, 30)
    }
    
    var list: some View {
        VStack(spacing: 0) {
            TokenCell()
            TokenCell()
            TokenCell()
            TokenCell()
            TokenCell()
        }
    }
    
    var addButton: some View {
        FilledButton(title: "chooseTokens", icon: "plus")
            .padding(16)
    }
}

#Preview {
    VaultDetailView()
}
