//
//  FilledButton.swift
//  VoltixApp
//
//  Created by Amol Kumar on 2024-03-06.
//

import SwiftUI

struct FilledButton: View {
    let title: String
    
    var body: some View {
        Text(NSLocalizedString(title, comment: "Button Text"))
            .font(.body16MontserratBold)
            .foregroundColor(.blue600)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color.turquoise600)
            .cornerRadius(100)
    }
}

#Preview {
    FilledButton(title: "start")
}
