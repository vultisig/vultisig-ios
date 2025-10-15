//
//  CoinActionsView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 11/09/2025.
//

import SwiftUI

struct CoinActionsView: View {
    let actions: [CoinAction]
    var onAction: (CoinAction) -> Void
    
    @State private var availableWidth: CGFloat = 0
    
    var calculatedSpacing: CGFloat {
        min(availableWidth / 20, 20)
    }
    
    var body: some View {
        HStack(spacing: calculatedSpacing) {
            ForEach(actions, id: \.self) { action in
                VStack {
                    CoinActionButton(
                        title: action.buttonTitle,
                        icon: action.buttonIcon,
                        isHighlighted: action.shouldHightlight
                    ) {
                        onAction(action)
                    }
                }
            }
        }
        .readSize { size in
            availableWidth = size.width
        }
    }
}

#Preview {
    VStack {
        CoinActionsView(actions: [.swap, .buy, .send, .receive]) { _ in
            
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .background(Theme.colors.bgPrimary)
}
