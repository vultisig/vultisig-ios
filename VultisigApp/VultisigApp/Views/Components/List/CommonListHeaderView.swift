//
//  CommonListHeaderView.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/09/2025.
//

import SwiftUI

struct CommonListHeaderView: View {
    let title: String
    let paddingTop: CGFloat?
    
    init(title: String, paddingTop: CGFloat? = nil) {
        self.title = title
        self.paddingTop = paddingTop
    }
    
    var body: some View {
        Text(title)
            .font(Theme.fonts.caption12)
            .foregroundStyle(Theme.colors.textTertiary)
            .background(Theme.colors.bgPrimary)
            .padding(.top, paddingTop ?? 16)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .plainListItem()
    }
}

#Preview {
    CommonListHeaderView(title: "Test")
}
