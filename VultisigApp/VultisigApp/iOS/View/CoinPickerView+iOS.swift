//
//  CoinPickerView+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(iOS)
import SwiftUI

extension CoinPickerView {
    var content: some View {
        ZStack {
            Background()
            main
        }
        .navigationBarBackButtonHidden(true)
        .navigationTitle(NSLocalizedString("chains", comment: "Chains"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: Placement.topBarLeading.getPlacement()) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.backward")
                        .font(.body18MenloBold)
                        .foregroundColor(Color.neutral0)
                }
            }
        }
    }
    
    var main: some View {
        view
    }
    
    var view: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
                .padding(.horizontal, 12)
                .padding(.top, 24)
            
            ScrollView {
                scrollView
                    .padding(.horizontal, 12)
                    .scrollContentBackground(.hidden)
                    .padding(.top, 20)
                    .padding(.bottom, 50)
            }
        }
    }
}
#endif
