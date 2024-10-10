//
//  RegisterVaultView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-10-09.
//

#if os(macOS)
import SwiftUI

extension RegisterVaultView {
    var view: some View {
        VStack {
            header
            image
            content
        }
    }
    
    var header: some View {
        GeneralMacHeader(title: "registerVault")
    }
    
    var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            text1
            text2
            text3
            text4
            Spacer()
            button
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.body16MenloBold)
        .foregroundColor(.neutral0)
        .padding(16)
    }
}
#endif
