//
//  ServerBackupVerificationHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-22.
//

import SwiftUI

struct ServerBackupVerificationHeader: View {

    var body: some View {
        HStack {
            leadingAction.opacity(0)
            Spacer()
            text
            Spacer()
            leadingAction.opacity(0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
        .background(Theme.colors.bgPrimary)
    }

    var leadingAction: some View {
        Image(systemName: "chevron.backward")
            .font(Theme.fonts.bodyLMedium)
            .foregroundColor(Theme.colors.textPrimary)
    }

    var text: some View {
        Text(NSLocalizedString("", comment: ""))
            .foregroundColor(Theme.colors.textPrimary)
            .font(.title3)
    }
}

#Preview {
    ServerBackupVerificationHeader()
}
