//
//  CoinPickerView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-18.
//

#if os(macOS)
import SwiftUI

extension CoinPickerView {
    var content: some View {
        ZStack {
            Background()
            view
        }
        .navigationBarBackButtonHidden(true)
        .crossPlatformToolbar("chains".localized)
    }

    var view: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
                .padding(.vertical, 18)
                .padding(.horizontal, 46)

            Separator()

            ScrollView {
                scrollView
                    .padding(.horizontal, 52)
                    .scrollContentBackground(.hidden)
                    .padding(.top, 20)
                    .padding(.bottom, 50)
            }
        }
    }
}
#endif
