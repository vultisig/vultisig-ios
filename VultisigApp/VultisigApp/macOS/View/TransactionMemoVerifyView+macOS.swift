//
//  TransactionMemoVerifyView+macOS.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-09-06.
//

#if os(macOS)
import SwiftUI

extension TransactionMemoVerifyView {
    var container: some View {
        content
        .padding(.horizontal, 25)
    }
}
#endif
