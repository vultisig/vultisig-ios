//
//  TokenSelectionView.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import SwiftUI

struct TokenSelectionView: View {
    @Binding var showTokenSelectionSheet: Bool
    
    var body: some View {
        ZStack {
            background
            view
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("tokens", comment: "Token Selection View title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationBackSheetButton(showSheet: $showTokenSelectionSheet)
            }
        }
    }
    
    var background: some View {
        Color.backgroundBlue
            .ignoresSafeArea()
    }
    
    var view: some View {
        ScrollView {
            
        }
    }
}

#Preview {
    TokenSelectionView(showTokenSelectionSheet: .constant(true))
}
