//
//  SendAddressBookView.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2025-06-30.
//

import SwiftUI

struct SendAddressBookView: View {
    var body: some View {
        VStack(spacing: 8) {
            title
        }
    }
    
    var title: some View {
        Text(NSLocalizedString("addressBook", comment: ""))
            .font(.body16MontserratMedium)
            .foregroundColor(.neutral0)
    }
}

#Preview {
    SendAddressBookView()
}
