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
        .background(Color.backgroundBlue)
    }
    
    var leadingAction: some View {
        Image(systemName: "chevron.backward")
            .font(.body18MenloBold)
            .foregroundColor(.neutral0)
    }
    
    var text: some View {
        Text(NSLocalizedString("serverBackupVerification", comment: ""))
            .foregroundColor(.neutral0)
            .font(.title3)
    }
}

#Preview {
    ServerBackupVerificationHeader()
}
