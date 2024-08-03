//
//  FilledLabelButton.swift
//  VultisigApp
//
//  Created by Artur Guseinov on 01.08.2024.
//

import SwiftUI

struct FilledLabelButton<Label>: View where Label: View {

    let label: Label

    init(@ViewBuilder _ label: () -> Label) {
        self.label = label()
    }

    var body: some View {
        ZStack {
            label
        }
        .frame(maxWidth: .infinity)
        .background(background)
        .cornerRadius(100)
    }

    var background: Color {
        Color.turquoise600
    }
}
