//
//  ServerBackupVerificationHeader.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-11-22.
//

import SwiftUI

struct ServerBackupVerificationHeader: View {
    @Binding var isLinkActive: Bool
    @Binding var setupLinkActive: Bool
    
    var body: some View {
        HStack {
            leadingAction
            Spacer()
            text
            Spacer()
            leadingAction.opacity(0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 40)
        .padding(.top, 8)
        .background(Color.backgroundBlue)
    }
    
    var leadingAction: some View {
        Button(action: {
            setupLinkActive = true
            isLinkActive = false
        }) {
            Image(systemName: "chevron.backward")
                .font(.body18MenloBold)
                .foregroundColor(.neutral0)
        }
    }
    
    var text: some View {
        Text(NSLocalizedString("serverBackupVerification", comment: ""))
            .foregroundColor(.neutral0)
            .font(.title3)
    }
}

#Preview {
    ServerBackupVerificationHeader(isLinkActive: .constant(false), setupLinkActive: .constant(false))
}
