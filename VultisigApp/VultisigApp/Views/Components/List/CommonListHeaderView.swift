//
//  CommonListHeaderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

struct CommonListHeaderView: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textExtraLight)
            .background(Theme.colors.bgPrimary)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .plainListItem()
    }
}

#Preview {
    CommonListHeaderView(title: "Test")
}
