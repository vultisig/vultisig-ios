//
//  JoinKeygenHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-08.
//

import SwiftUI

struct JoinKeygenHeader: View {
    let title: String
    var hideBackButton: Bool = false

    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            trailingAction
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }

    var leadingAction: some View {
        NavigationBackButton()
            .opacity(hideBackButton ? 0 : 1)
    }

    var text: some View {
        Text(NSLocalizedString(title, comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(.title3)
    }

    var trailingAction: some View {
        NavigationHelpButton()
    }
}

#Preview {
    JoinKeygenHeader(title: "joinKeygen", hideBackButton: false)
}
