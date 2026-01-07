//
//  CircleDepositView+iOS.swift
//  VultisigApp
//
//  Created by Enrique Souza on 2025-12-13.
//

import SwiftUI

#if os(iOS)
extension CircleDepositView {
    var main: some View {
        ZStack {
            VaultMainScreenBackground()
            content
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            Task { await loadData() }
        }
    }
    
    var scrollView: some View {
        ScrollView {
            scrollableContent
        }
    }
}
#endif
