//
//  CreateVaultHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-08-09.
//

import SwiftUI

struct CreateVaultHeader: View {
    let showBackButton: Bool

    var body: some View {
        HStack {
            leadingAction
            Spacer()
            trailingAction
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
    }

    var leadingAction: some View {
        ZStack {
            if showBackButton {
                NavigationBackButton()
            }
        }
    }

    var trailingAction: some View {
        NavigationHelpButton()
    }
}

#Preview {
    CreateVaultHeader(showBackButton: true)
}
