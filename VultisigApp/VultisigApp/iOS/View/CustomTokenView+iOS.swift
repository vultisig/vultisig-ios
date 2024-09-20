//
//  CustomTokenView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-19.
//

#if os(iOS)
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
        .navigationTitle(NSLocalizedString("findCustomTokens", comment: "Find Your Custom Token"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                Button(action: {
                    self.chainDetailView.sheetType = nil
                    dismiss()
                }) {
                    Image(systemName: "chevron.backward")
                        .font(.body18Menlo)
                        .foregroundColor(Color.neutral0)
                }
            }
        }
    }
    
    var main: some View {
        view
            .padding(.top, 16)
            .padding(.horizontal, 16)
}
}
#endif
