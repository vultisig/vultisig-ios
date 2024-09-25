//
//  KeygenViewInstructions+iOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-25.
//

#if os(iOS)
import SwiftUI

extension KeygenViewInstructions {
    func setIndicator() {
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(Color.turquoise400)
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(Color.blue200)
    }
    
    var cards: some View {
        TabView(selection: $tabIndex) {
            ForEach(0..<7) { index in
                getCard(for: index)
            }
        }
        .tabViewStyle(PageTabViewStyle())
        .frame(maxHeight: .infinity)
        .foregroundColor(.blue)
    }
}
#endif
