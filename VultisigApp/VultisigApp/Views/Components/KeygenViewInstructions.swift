//
//  KeygenViewInstructions.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-31.
//

import SwiftUI

struct KeygenViewInstructions: View {
    @State var tabIndex = 0
    
#if os(iOS)
    init() {
        UIPageControl.appearance().currentPageIndicatorTintColor = UIColor(Color.turquoise400)
        UIPageControl.appearance().pageIndicatorTintColor = UIColor(Color.blue200)
    }
#endif
    
    var body: some View {
        cards
            .frame(maxHeight: 250)
    }
    
    var cards: some View {
        TabView(selection: $tabIndex) {
            ForEach(0..<7) { index in
                getCard(for: index)
            }
        }
#if os(iOS)
        .tabViewStyle(PageTabViewStyle())
#endif
        .frame(maxHeight: .infinity)
        .foregroundColor(.blue)
    }
    
    private func getCard(for index: Int) -> some View {
        VStack(spacing: 22) {
            getTitle(for: index)
            getDescription(for: index)
        }
        .tag(index)
        .frame(maxWidth: 280)
    }
    
    private func getTitle(for index: Int) -> some View {
        Text(NSLocalizedString("keygenInstructionsCar\(index+1)Title", comment: ""))
            .foregroundColor(.neutral0)
            .font(.body16MontserratBold)
    }
    
    private func getDescription(for index: Int) -> some View {
        Group {
            Text(NSLocalizedString("keygenInstructionsCar\(index+1)DescriptionPart1", comment: ""))
                .foregroundColor(.neutral0)
                .font(.body14MontserratSemiBold) +
            Text(NSLocalizedString("keygenInstructionsCar\(index+1)DescriptionPart2", comment: ""))
                .foregroundColor(.turquoise400)
                .font(.body14MontserratSemiBold) +
            Text(NSLocalizedString("keygenInstructionsCar\(index+1)DescriptionPart3", comment: ""))
                .foregroundColor(.neutral0)
                .font(.body14MontserratSemiBold)
        }
        .multilineTextAlignment(.center)
    }
}

#Preview {
    ZStack {
        Background()
        KeygenViewInstructions()
    }
}
