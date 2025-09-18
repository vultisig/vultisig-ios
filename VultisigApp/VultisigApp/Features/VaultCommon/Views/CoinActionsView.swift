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
    
    var body: some View {
        HStack(spacing: 20) {
            ForEach(actions, id: \.self) { action in
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
}

#Preview {
    VStack {
        CoinActionsView(actions: [.swap, .buy, .send, .receive]) { _ in
            
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    .background(Theme.colors.bgPrimary)
}
