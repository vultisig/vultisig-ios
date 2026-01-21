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
        guard actions.count > 1 else { return 0 }
        let buttonWidth: CGFloat = 52
        let totalButtonWidth = CGFloat(actions.count) * buttonWidth
        let availableSpaceForSpacing = availableWidth - totalButtonWidth
        let numberOfSpaces = CGFloat(actions.count - 1)

        guard numberOfSpaces > 0 && availableSpaceForSpacing > 0 else { return 0 }

        let calculatedFromAvailableSpace = availableSpaceForSpacing / numberOfSpaces
        return min(max(calculatedFromAvailableSpace, 8), 20) // Min 8pt, max 20pt
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
        .frame(maxWidth: .infinity)
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
