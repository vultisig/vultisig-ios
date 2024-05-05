//
//  KeygenStatusText.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-04-16.
//

import SwiftUI

struct KeygenStatusText: View {
    let status: String
    
    var body: some View {
        HStack {
            Text(self.status)
                .font(.body15MenloBold)
                .foregroundColor(.neutral0)
                .multilineTextAlignment(.center)
            
            ProgressView()
                .progressViewStyle(.circular)
                .padding(2)
                .foregroundColor(.neutral0)
        }
    }
}

#Preview {
    KeygenStatusText(status: "preparingVault")
}
