//
//  CustomTokenView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(macOS)
import SwiftUI

extension CustomTokenView {
    var content: some View {
        ZStack {
            Background()
            VStack(alignment: .leading) {
                main
                
                if let error = error {
                    errorView(error: error)
                }
                
                if isLoading {
                    Loader()
                }
                
                Spacer()
            }
        }
        .task {
            await tokenViewModel.loadData(groupedChain: group)
        }
        .navigationBarBackButtonHidden(true)
    }
    
    var main: some View {
        VStack(spacing: 0) {
            headerMac
            view
                .padding(.top, 16)
                .padding(.horizontal, 16)
        }
    }
    
    var headerMac: some View {
        TokenSelectionHeader(title: "findCustomTokens", chainDetailView: chainDetailView)
    }
}
#endif
