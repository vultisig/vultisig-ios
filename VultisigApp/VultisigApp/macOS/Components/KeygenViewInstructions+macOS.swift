//
//  KeygenViewInstructions+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-25.
//

#if os(macOS)
import SwiftUI

extension KeygenViewInstructions {
    func setIndicator() {}

    var cards: some View {
        TabView(selection: $tabIndex) {
            ForEach(0..<7) { index in
                getCard(for: index)
            }
        }
        .frame(maxHeight: .infinity)
        .foregroundColor(.blue)
    }
}
#endif
